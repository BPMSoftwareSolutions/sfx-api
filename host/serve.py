#!/usr/bin/env python3
"""The sfx-api hosting facade.

The platform's HTTP server receives a request; the facade hands it, as the raw text the platform
read, to a resident kernel as one sfx-command-delivery.v1 envelope invoking the declared capability
serve-http-request, and writes back the raw HTTP response the kernel resolves. Every mechanic of the
API is declared and resolved by the kernel: the request target, query and body, the credential carrier
and its session digest, the operation, the caller, the run, refusals and the response itself. The
kernels keep running between requests (--resident-envelopes: one envelope per line on stdin, one
delivery per line on stdout), so no request pays a kernel start.

A run outlives the request that admits it, so a response cannot carry it. For a run the kernel
answers a host directive instead: a response of type application/vnd.sfx.host-directive+json, written
only by the declared capabilities the interface resolves to. The facade does what it says:

- execute-run: answer the directive's response (202 with the run), then execute the run's observe
  envelope on a worker kernel started with SIDEFX_OBSERVE=1. Each observation the kernel writes while
  the run executes becomes the run's next event and reaches every listener as it is written. When the
  run ends, the facade retains its events through the directive's trace capability, contiguous chunk
  by chunk, invokes its completion capability with the last retained cursor, and only then ends the
  run.
- stream-run: answer server-sent events: the run's events after the cursor (or Last-Event-ID), then
  each new event as it arrives, then an end event once the run has ended. A session caller's stream
  ends instead at the session's expiry, or at the first recheck (the directive's capability, at its
  interval) that cannot confirm the session.
- respond: answer the directive's response.

The kernel commands, pool sizes, answer bounds, the envelope's request and the run bounds are host
data in sfx-api.config.json. Python standard library only: nothing is installed or built.

    python3 host/serve.py sfx-api.config.json
"""
import datetime
import http
import http.server
import json
import os
import queue
import subprocess
import sys
import threading
import time

host = json.load(open(sys.argv[1], encoding='utf-8'))
DIRECTIVE = 'application/vnd.sfx.host-directive+json'
OBSERVATION = 'SFX_OBSERVATION '


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


class Kernel:
    """One resident kernel, started on first use and again after it exits or overruns the bound. A worker
    kernel's observation lines go to the run it is executing; its other diagnostics go to the host log."""

    process = None
    run = None

    def __init__(self, settings):
        self.settings = settings

    def deliver(self, envelope):
        if self.process is None or self.process.poll() is not None:
            observed = 'environment' in self.settings
            self.process = subprocess.Popen(self.settings['command'], cwd=host['kernel']['root'],
                                            env=dict(os.environ, **self.settings.get('environment', {})),
                                            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                            stderr=subprocess.PIPE if observed else None)
            self.lines = queue.Queue()
            threading.Thread(target=self.read, args=(self.process.stdout, self.lines), daemon=True).start()
            if observed:
                threading.Thread(target=self.observe, args=(self.process.stderr,), daemon=True).start()
        self.process.stdin.write(json.dumps(envelope, separators=(',', ':')).encode('utf-8') + b'\n')
        self.process.stdin.flush()
        try:
            line = self.lines.get(timeout=self.settings['answerTimeoutMs'] / 1000)
        except queue.Empty:
            line = b''
        if not line:
            self.process.kill()
            self.process = None
        return json.loads(line)

    @staticmethod
    def read(stdout, lines):
        for line in stdout:
            lines.put(line)
        lines.put(b'')

    def observe(self, stderr):
        for line in stderr:
            text = line.decode('utf-8', 'replace').rstrip('\r\n')
            if text.startswith(OBSERVATION):
                run = self.run
                if run is not None:
                    run.observe(text[len(OBSERVATION):])
            elif text:
                sys.stderr.write(text + '\n')


class Run:
    """One run this host executes: its events in order, and the condition every listener waits on."""

    def __init__(self, directive):
        self.directive = directive
        self.run_id = directive['runId']
        self.events = []
        self.dropped = 0
        self.state = 'admitted'
        self.ended = False
        self.changed = threading.Condition()
        self.append('run.admitted', {'capability': directive.get('capability'), 'admittedAt': directive.get('admittedAt')})

    def append(self, kind, payload):
        with self.changed:
            cursor = len(self.events) + 1
            event = {'eventId': 'urn:sfx-api:run-event:%s:%d' % (self.run_id, cursor), 'cursor': cursor, 'at': now(),
                     'kind': kind, 'payload': payload}
            if isinstance(payload, dict) and isinstance(payload.get('rootExecutionId'), str):
                event['rootExecutionId'] = payload['rootExecutionId']
            self.events.append(event)
            self.changed.notify_all()

    def observe(self, text):
        if len(self.events) >= host['runs']['maxEvents']:
            self.dropped += 1
            return
        try:
            record = json.loads(text)
        except ValueError:
            self.append('observation.malformed', {'line': text[:1024]})
            return
        kind = record.get('observationType') if isinstance(record, dict) else None
        if len(text) > host['runs']['eventPayloadBytes']:
            kept = record if isinstance(record, dict) else {}
            record = {'truncated': True, 'byteLength': len(text.encode('utf-8')),
                      **{key: kept[key] for key in ('observationType', 'testimonyType', 'graphId', 'rootExecutionId',
                                                   'cellId', 'phase', 'status') if key in kept}}
        self.append(kind if isinstance(kind, str) else 'observation', record)

    def end(self, state):
        with self.changed:
            self.state, self.ended = state, True
            self.changed.notify_all()

    def after(self, cursor, timeout):
        """The events after the cursor, waiting up to the timeout for one, and whether the run has ended."""
        with self.changed:
            if len(self.events) <= cursor and not self.ended:
                self.changed.wait(timeout)
            return self.events[cursor:], self.ended


def settle(delivery):
    """The run's state, exit code, failure and output from the worker kernel's delivery."""
    result = (delivery.get('outcome') or {}).get('result') or {}
    if delivery.get('disposition') == 'terminated' and result.get('disposition') == 'completed':
        return 'completed', 0, None, result.get('outcome')
    failure = (delivery.get('error') or result.get('failure') or (delivery.get('outcome') or {}).get('error')
               or {'code': 'RUN_FAILED', 'message': str(result.get('disposition') or delivery.get('disposition'))})
    return 'failed', 1, failure, None


def invoke(kernel, capability_id, payload):
    """One declared capability on a kernel; its outcome, or None when the kernel does not answer."""
    try:
        delivery = kernel.deliver({'deliveryType': 'sfx-command-delivery.v1', 'operation': 'invoke', 'request': {
            'object': 'capability', 'verb': 'invoke', 'subject': capability_id, 'input': payload, 'inputType': 'json'}})
    except (ValueError, OSError):
        return None
    return ((delivery.get('outcome') or {}).get('result') or {}).get('outcome')


def chunks(events):
    """Contiguous runs of events within the trace chunk bounds."""
    chunk, size = [], 0
    for event in events:
        length = len(json.dumps(event, separators=(',', ':')).encode('utf-8'))
        if chunk and (size + length > host['runs']['traceChunkBytes'] or len(chunk) >= host['runs']['traceChunkEvents']):
            yield chunk
            chunk, size = [], 0
        chunk.append(event)
        size += length
    if chunk:
        yield chunk


def instant(text):
    """An ISO 8601 instant as a UTC datetime, or None."""
    if not isinstance(text, str):
        return None
    fixed = text.replace('Z', '+00:00')
    whole, dot, rest = fixed.partition('.')
    if dot:
        digits = len(rest) - len(rest.lstrip('0123456789'))
        fixed = whole + '.' + rest[:min(digits, 6)].ljust(6, '0') + rest[digits:]
    try:
        return datetime.datetime.fromisoformat(fixed).astimezone(datetime.timezone.utc)
    except ValueError:
        return None


class Sessions:
    """The declared session recheck of open streams, its answer shared for one interval per session."""

    def __init__(self):
        self.lock = threading.Lock()
        self.checked = {}

    def live(self, recheck):
        key = json.dumps(recheck['input'], sort_keys=True)
        interval = recheck['intervalMilliseconds'] / 1000
        with self.lock:
            at, answer = self.checked.get(key, (None, None))
            if at is not None and time.monotonic() - at < interval:
                return answer
        kernel = kernels.get()
        try:
            outcome = invoke(kernel, recheck['capabilityId'], recheck['input'])
        finally:
            kernels.put(kernel)
        answer = isinstance(outcome, dict) and outcome.get('status') == 'LIVE'
        with self.lock:
            self.checked[key] = (time.monotonic(), answer)
        return answer


class Runs:
    """The runs this host has admitted, the retained bound of ended ones, and the queue the workers take."""

    def __init__(self):
        self.lock = threading.Lock()
        self.runs = {}
        self.pending = queue.Queue()

    def admit(self, directive):
        with self.lock:
            if directive['runId'] in self.runs:
                return
            run = self.runs[directive['runId']] = Run(directive)
            ended = [run_id for run_id, known in self.runs.items() if known.ended]
            for run_id in ended[:max(0, len(self.runs) - host['runs']['retained'])]:
                del self.runs[run_id]
        self.pending.put(run)

    def get(self, run_id):
        with self.lock:
            return self.runs.get(run_id)

    def work(self, kernel):
        while True:
            run = self.pending.get()
            run.state, started = 'executing', now()
            run.append('run.started', {'startedAt': started})
            kernel.run = run
            try:
                delivery = kernel.deliver(run.directive['envelope'])
            except (ValueError, OSError) as error:
                delivery = {'disposition': 'failed', 'error': {'code': 'RUN_KERNEL_FAILED', 'message': type(error).__name__}}
            kernel.run = None
            state, exit_code, failure, output = settle(delivery)
            ended = now()
            run.append('run.exited', {'state': state, 'exitCode': exit_code, 'endedAt': ended,
                                      **({'failure': failure} if failure else {}),
                                      **({'droppedEvents': run.dropped} if run.dropped else {})})
            completion = dict(run.directive['completion']['input'], state=state, exitCode=exit_code,
                              startedAt=started, endedAt=ended)
            if failure:
                completion['failure'] = failure
            if isinstance(output, (dict, list)):
                completion['output'] = output
            trace = run.directive.get('trace')
            if trace:
                completion['latestCursor'] = 0
                for chunk in chunks(run.events):
                    answer = invoke(kernel, trace['capabilityId'], {
                        'runId': run.run_id, 'firstCursor': chunk[0]['cursor'], 'lastCursor': chunk[-1]['cursor'],
                        'recordCount': len(chunk), 'events': chunk})
                    if not isinstance(answer, dict) or answer.get('status') != 'APPENDED':
                        sys.stderr.write('[sfx-api run %s] trace chunk %d..%d answered %s\n' % (
                            run.run_id, chunk[0]['cursor'], chunk[-1]['cursor'], json.dumps(answer)[:500]))
                        break
                    completion['latestCursor'] = chunk[-1]['cursor']
            answer = invoke(kernel, run.directive['completion']['capabilityId'], completion)
            if not isinstance(answer, dict) or answer.get('status') != 'COMPLETED':
                sys.stderr.write('[sfx-api run %s] completion answered %s\n' % (run.run_id, json.dumps(answer)[:500]))
            run.end(state)


kernels = queue.Queue()
for _ in range(host['kernel']['instances']):
    kernels.put(Kernel(host['kernel']))
sessions = Sessions()
runs = Runs()
for _ in range(host['workers']['instances']):
    threading.Thread(target=runs.work, args=(Kernel(host['workers']),), daemon=True).start()


class Facade(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def answer(self):
        raw = (self.raw_requestline + str(self.headers).encode('latin-1')
               + self.rfile.read(int(self.headers.get('content-length', 0)))).decode('utf-8', 'replace')
        kernel = kernels.get()
        try:
            response = kernel.deliver({'deliveryType': 'sfx-command-delivery.v1', 'operation': 'invoke',
                                       'request': dict(host['request'], input=raw)})['outcome']['result']['outcome']
        finally:
            kernels.put(kernel)
        head, _, body = response.partition('\r\n\r\n')
        types = [value.strip() for name, _, value in (line.partition(':') for line in head.split('\r\n')[1:])
                 if name.strip().lower() == 'content-type']
        if types != [DIRECTIVE]:
            self.wfile.write(response.encode('utf-8'))
            return
        directive = json.loads(body)
        if directive['directive'] == 'stream-run':
            self.stream(directive)
            return
        if directive['directive'] == 'execute-run':
            runs.admit(directive['run'])
        self.respond(directive['respond'])

    def respond(self, response):
        body = json.dumps(response['body'], separators=(',', ':')).encode('utf-8')
        self.wfile.write(('HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\n'
                          'Connection: close\r\n\r\n' % (response['status'], http.HTTPStatus(response['status']).phrase,
                                                          response['contentType'], len(body))).encode('latin-1') + body)

    def stream(self, directive):
        """Server-sent events of a run, ended at the run's end, or at the caller session's expiry or the first
        declared recheck that cannot confirm the session."""
        self.close_connection = True
        cursor = directive.get('after')
        if cursor is None and (self.headers.get('last-event-id') or '').strip().isdigit():
            cursor = int(self.headers['last-event-id'].strip())
        cursor, state = max(0, cursor or 0), directive.get('state') or 'unknown'
        run = runs.get(directive['runId'])
        session = directive.get('session') or {}
        expires, recheck = instant(session.get('expiresAt')), session.get('recheck')
        keepalive = host['runs']['keepaliveSeconds']
        wrote = checked = time.monotonic()
        try:
            self.wfile.write(('HTTP/1.1 200 OK\r\nContent-Type: %s\r\nCache-Control: no-cache, no-store\r\n'
                              'X-Accel-Buffering: no\r\nConnection: close\r\n\r\n: sfx-api run event stream\n\n'
                              % directive['respond']['contentType']).encode('latin-1'))
            self.wfile.flush()
            while run is not None:
                wait = keepalive - (time.monotonic() - wrote)
                if recheck:
                    wait = min(wait, recheck['intervalMilliseconds'] / 1000 - (time.monotonic() - checked))
                if expires:
                    wait = min(wait, (expires - datetime.datetime.now(datetime.timezone.utc)).total_seconds())
                events, ended = run.after(cursor, max(0.05, wait))
                if events:
                    cursor = events[-1]['cursor']
                    self.wfile.write(''.join('id: %d\nevent: %s\ndata: %s\n\n' % (
                        event['cursor'], event['kind'], json.dumps(event, separators=(',', ':'))) for event in events).encode('utf-8'))
                    wrote = time.monotonic()
                elif not ended and time.monotonic() - wrote >= keepalive:
                    self.wfile.write(b': keepalive\n\n')
                    wrote = time.monotonic()
                self.wfile.flush()
                if ended:
                    state = run.state
                    break
                if expires and datetime.datetime.now(datetime.timezone.utc) >= expires:
                    return self.session_ended(directive['runId'], cursor)
                if recheck and time.monotonic() - checked >= recheck['intervalMilliseconds'] / 1000:
                    if not sessions.live(recheck):
                        return self.session_ended(directive['runId'], cursor)
                    checked = time.monotonic()
            self.wfile.write(('event: end\ndata: %s\n\n' % json.dumps(
                {'runId': directive['runId'], 'state': state, 'cursor': cursor}, separators=(',', ':'))).encode('utf-8'))
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            return

    def session_ended(self, run_id, cursor):
        self.wfile.write(('event: session-ended\ndata: %s\n\n' % json.dumps(
            {'runId': run_id, 'cursor': cursor}, separators=(',', ':'))).encode('utf-8'))
        self.wfile.flush()

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = answer


http.server.ThreadingHTTPServer((host['http']['host'], host['http']['port']), Facade).serve_forever()
