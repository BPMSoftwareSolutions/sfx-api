#!/usr/bin/env python3
"""The sfx-api hosting facade.

The platform's HTTP server receives a request; the facade hands it, as the raw text the platform read, to a resident
kernel in the envelope the host's declared settings name, and writes back the raw HTTP response the kernel resolves.
Every meaning of the API is declared and resolved by the kernel. The facade holds connections, starts and supervises
kernels, writes what they answer and fans in what they write; it decides nothing itself. The kernels keep running
between requests (--resident-envelopes: one envelope per line on stdin, one delivery per line on stdout), so no request
pays a kernel start.

At start, before it listens, the facade delivers read-api-host-configuration to every request kernel, the publisher
and the drawing reader, so each one admits the host's bundle, and holds the answer as its settings for as long as it
runs (api-host-configuration.v1). A kernel that does not answer, or settings the facade cannot carry out, stop the host.
A run worker starts on its first run.

A run outlives the request that admits it, so its admission answers a host directive: a response of type
application/vnd.sfx.host-directive+json whose body names sfx-api-host-directive.v1. The facade carries out what it
says, and answers any other with the declared failure response:

- execute-run: write respond.raw, or the declared queue refusal when the declared queue has no room, and end that run
  with the declared delivery answer; execute run.envelope on a worker kernel; hand the run's admission, start,
  observations and end to run.events and keep each event and frame as answered; retain the trace through run.trace;
  complete through run.completion; and only once the completion answers COMPLETED, write the run's end to its streams,
  publish it, and capture the run through run.facts.
- respond: write respond.raw.
- stream-run: write stream.head and stream.open; each event's frame after the declared cursor, as run.events answered
  it; stream.keepalive while quiet; the end frame run.events answered, or stream.end for a run the facade does not
  hold; stream.sessionEnded, with the last cursor in place of {cursor}, when the session ends.
- stream-estate: write head, with the channel instance in place of {instance}, and frames.open; replay after the
  declared cursor, or every retained frame when it is beyond the latest position; frames.replayComplete; then each
  frame as it is published, following select; frames.keepalive while quiet; end at bound, or with frames.sessionEnded
  when the session ends.

The events of every run whose plan is published, and every drawing change event the declared drawing read answers, go
to the estate's live observation channel at the position the channel reserves for them. The publish capability frames
each batch on a kernel of its own; the channel keeps each frame exactly as answered, with the run window it names.

The facade's own configuration holds only how to listen and, for each kind of kernel, its command, its number of
instances and its answer bound, in one kernel install root. Python standard library only: nothing is installed or built.

    python3 host/serve.py sfx-api.config.json
"""
import collections
import copy
import datetime
import http.server
import itertools
import json
import queue
import subprocess
import sys
import threading
import time
import uuid

host = json.load(open(sys.argv[1], encoding='utf-8'))
DIRECTIVE = 'application/vnd.sfx.host-directive+json'
CONTRACT = 'sfx-api-host-directive.v1'
SETTINGS = 'read-api-host-configuration'
OBSERVATION = 'SFX_OBSERVATION '
FRAMES = ('observation-stream-opened.v1', 'observation-stream-closed.v1')
settings = None


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


class Stream:
    """One kernel process's observation stream: the closing frame of each delivery it observed, by the delivery's
    ref, and whether the stream is still open."""

    def __init__(self):
        self.changed = threading.Condition()
        self.closed = {}
        self.open = True


class Kernel:
    """One resident kernel, started with the host and again after it exits, overruns its bound or answers what is not
    JSON. The observations a delivery's declared ref frames go to the run expecting that ref; a line no expected ref
    frames is not published; its other diagnostics go to the host log."""

    process = None
    stream = None

    def __init__(self, kind):
        self.kind = kind
        self.expected = {}

    def deliver(self, envelope):
        """One envelope to the running kernel and its answer, delivered once, as one line of UTF-8: unescaped, so a
        result of the profile's maximumResultBytes fits the kernel's 8 MiB line. A kernel that ended before holding the
        whole line answers it with what it wrote before ending, or, having written nothing, is started again and given
        it; one that ends or overruns its bound without answering answers KERNEL_EXITED or KERNEL_TIMEOUT, and one that
        answers what is not a JSON object answers KERNEL_ANSWER_INVALID; each of these is stopped. A delivery without an
        outcome goes to the host log whole."""
        text = json.dumps(envelope, separators=(',', ':'), ensure_ascii=False)
        try:
            line = text.encode('utf-8') + b'\n'
        except UnicodeEncodeError:
            # A lone surrogate has no UTF-8 form; the line keeps it escaped.
            line = json.dumps(envelope, separators=(',', ':')).encode('ascii') + b'\n'
        bound = self.kind['answerTimeoutMs'] / 1000
        answer = b''
        for _ in range(2):
            if self.process is None or self.process.poll() is not None:
                self.start()
            try:
                self.process.stdin.write(line)
                self.process.stdin.flush()
            except OSError:
                # It ended before the whole line reached it, so it cannot have begun the envelope. What it answered
                # before ending answers it; a kernel that answered nothing was given nothing.
                try:
                    answer = self.lines.get(timeout=bound)
                except queue.Empty:
                    answer = None
                if answer != b'':
                    break
                self.process = None
                continue
            try:
                answer = self.lines.get(timeout=bound)
            except queue.Empty:
                answer = None
            break
        delivery = None
        if answer:
            try:
                delivery = json.loads(answer)
            except ValueError:
                pass
            if not isinstance(delivery, dict):
                self.stop()
                delivery = {'disposition': 'failed', 'errorCode': 'KERNEL_ANSWER_INVALID',
                            'error': {'code': 'KERNEL_ANSWER_INVALID', 'message': answer.decode('utf-8', 'replace')}}
        else:
            code = 'KERNEL_TIMEOUT' if answer is None else 'KERNEL_EXITED'
            self.stop()
            delivery = {'disposition': 'failed', 'errorCode': code, 'error': {'code': code}}
        if 'outcome' not in delivery:
            sys.stderr.write('[sfx-api kernel] %s %s\n' % (envelope['request'].get('subject'),
                                                          json.dumps(delivery.get('error') or delivery)))
        return delivery

    def start(self):
        self.process = subprocess.Popen(self.kind['command'], cwd=host['kernel']['root'],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.lines = queue.Queue()
        self.stream = Stream()
        threading.Thread(target=self.read, args=(self.process.stdout, self.lines), daemon=True).start()
        threading.Thread(target=self.observe, args=(self.process.stderr, self.stream), daemon=True).start()

    def stop(self):
        if self.process is not None:
            self.process.kill()
        self.process = None

    @staticmethod
    def read(stdout, lines):
        for line in stdout:
            lines.put(line)
        lines.put(b'')

    def capture(self, envelope):
        """The kernel's closing frame for the observations the envelope asked for, once it has written them all, or None
        when its stream ended without one. The kernel writes them from its own queue, so the closing frame can come after
        the answer: the end is that frame or the stream's end, never silence."""
        observation = envelope.get('observation')
        if not (isinstance(observation, dict) and observation.get('sample') is True):
            return None
        stream, ref = self.stream, observation.get('ref')
        with stream.changed:
            while ref not in stream.closed and stream.open:
                stream.changed.wait()
            return stream.closed.pop(ref, None)

    def observe(self, stderr, stream):
        framing = None
        for line in stderr:
            text = line.decode('utf-8', 'replace').rstrip('\r\n')
            if not text.startswith(OBSERVATION):
                if text:
                    sys.stderr.write(text + '\n')
                continue
            text = text[len(OBSERVATION):]
            if '"observation-stream-' in text:
                try:
                    frame = json.loads(text)
                except ValueError:
                    frame = None
                if isinstance(frame, dict) and frame.get('observationType') in FRAMES:
                    if frame['observationType'] == FRAMES[0]:
                        framing = frame.get('ref')
                    else:
                        with stream.changed:
                            stream.closed[frame.get('ref')] = frame
                            stream.changed.notify_all()
                        if frame.get('ref') == framing:
                            framing = None
                    continue
            run = self.expected.get(framing) if framing is not None else None
            if run is not None:
                run.observe(text)
        with stream.changed:
            stream.open = False
            stream.changed.notify_all()


def invoke(kernel, capability_id, payload):
    """One declared capability on a kernel, unsampled; its outcome, or None when the kernel does not answer."""
    delivery = kernel.deliver({'deliveryType': 'sfx-command-delivery.v1', 'operation': 'invoke', 'request': {
        'object': 'capability', 'verb': 'invoke', 'subject': capability_id, 'input': payload, 'inputType': 'json'}})
    return ((delivery.get('outcome') or {}).get('result') or {}).get('outcome')


def bookkeep(capability_id, payload):
    """One bookkeeping capability on the drawing reader's kernel, never a request kernel; its outcome or None. The
    drawing reader takes its kernel the same way, so the two never deliver to it at once."""
    kernel = bookkeepers.get()
    try:
        return invoke(kernel, capability_id, payload)
    finally:
        bookkeepers.put(kernel)


class Run:
    """One run this host executes, as its execute-run directive's plan declares it. Its events and their frames are the
    ones run.events answered; its run.exited and end frame reach its streams once its completion is stored."""

    def __init__(self, plan):
        self.plan = plan
        self.run_id = plan['runId']
        self.events = []
        self.dropped = 0
        self.exited = None
        self.end_frame = None
        self.ended = False
        self.finished = False
        self.broken = False
        self.observed = []
        self.projecting = 0
        self.changed = threading.Condition()
        threading.Thread(target=self.project, daemon=True).start()

    def identity(self):
        """The run as the channel publishes it: its id and its capability."""
        return {'executionId': self.run_id, 'capability': self.plan.get('capability')}

    def note(self, item):
        """Something the facade observed of the run, for run.events in the order observed."""
        with self.changed:
            self.observed.append(item)
            self.changed.notify_all()

    def observe(self, text):
        self.note({'kind': 'line', 'at': now(), 'line': text, 'byteLength': len(text.encode('utf-8'))})

    def project(self):
        """Hand run.events, in order, everything observed of the run since its last call, and keep each answer: an event
        with its frame, or a drop it counts. A call it does not answer item by item stops the run's events."""
        declared = self.plan['events']
        while True:
            with self.changed:
                while not self.observed:
                    self.changed.wait()
                batch, self.observed = self.observed, []
                self.projecting = len(batch)
                held = len(self.events)
            answer = bookkeep(declared['capabilityId'], {
                'run': {'runId': self.run_id, 'admittedAt': self.plan.get('admittedAt'),
                        'capability': self.plan.get('capability')},
                'bounds': settings['runs']['events'], 'held': held, 'observed': batch})
            answers = answer.get('answers') if isinstance(answer, dict) else None
            if not (isinstance(answers, list) and len(answers) == len(batch) and all(
                    each.get('dropped') is True or isinstance(each.get('event'), dict)
                    and isinstance(each['event'].get('cursor'), int) and isinstance(each.get('frame'), str)
                    and (item['kind'] != 'ended' or isinstance(each.get('end'), str))
                    for each, item in zip((each if isinstance(each, dict) else {} for each in answers), batch))):
                sys.stderr.write('[sfx-api run %s] %s answered %s\n' % (
                    self.run_id, declared['capabilityId'], json.dumps(answer)))
                with self.changed:
                    self.broken, self.projecting = True, 0
                    self.changed.notify_all()
                return
            with self.changed:
                for each, item in zip(answers, batch):
                    if each.get('dropped') is True:
                        self.dropped += 1
                    elif item['kind'] == 'ended':
                        self.exited = (each['event'], each['frame'], each['end'])
                    else:
                        self.events.append((each['event'], each['frame']))
                        if self.plan.get('published') is True:
                            channel.append(self, each['event'], each['event'].get('at'))
                self.projecting = 0
                self.changed.notify_all()
                if self.exited is not None:
                    return

    def settle(self):
        """Wait until everything observed of the run has been answered; whether its events still stand."""
        with self.changed:
            while (self.observed or self.projecting) and not self.broken:
                self.changed.wait()
            return not self.broken

    def end(self):
        """The run's run.exited and end frame, to its streams."""
        with self.changed:
            event, frame, self.end_frame = self.exited
            self.events.append((event, frame))
            self.ended = True
            self.changed.notify_all()

    def finish(self):
        with self.changed:
            self.finished = True
            self.changed.notify_all()

    def after(self, cursor, timeout):
        """The events after the cursor, as (event, frame), waiting up to the timeout for one, and whether the run's end is
        out."""
        with self.changed:
            if len(self.events) <= cursor and not self.ended:
                self.changed.wait(timeout)
            return self.events[cursor:], self.ended


def chunks(events):
    """Contiguous runs of events within the declared trace chunk bounds."""
    bounds = settings['runs']['trace']
    chunk, size = [], 0
    for event in events:
        length = len(json.dumps(event, separators=(',', ':')).encode('utf-8'))
        if chunk and (size + length > bounds['chunkBytes'] or len(chunk) >= bounds['chunkEvents']):
            yield chunk
            chunk, size = [], 0
        chunk.append(event)
        size += length
    if chunk:
        yield chunk


def finish(run, delivery, closing, started):
    """End a run as its plan declares: its end to run.events, its trace retained, its completion stored, and only once
    that is COMPLETED its end written to its streams, published and the run captured into the estate's facts. A run whose
    completion is not COMPLETED publishes no end, and its streams end when their session does."""
    plan = run.plan
    if run.settle():
        run.note({'kind': 'ended', 'at': now(), 'delivery': delivery, 'closing': closing, 'dropped': run.dropped})
    if not run.settle() or run.exited is None:
        sys.stderr.write('[sfx-api run %s] its events stopped before its end; it is not completed\n' % run.run_id)
        run.finish()
        return
    exited = run.exited[0]
    latest = 0
    for chunk in chunks([event for event, _ in run.events] + [exited]):
        answer = bookkeep(plan['trace']['capabilityId'], {
            'runId': run.run_id, 'firstCursor': chunk[0]['cursor'], 'lastCursor': chunk[-1]['cursor'],
            'recordCount': len(chunk), 'events': chunk})
        if not isinstance(answer, dict) or answer.get('status') != 'APPENDED':
            sys.stderr.write('[sfx-api run %s] trace chunk %d..%d answered %s\n' % (
                run.run_id, chunk[0]['cursor'], chunk[-1]['cursor'], json.dumps(answer)))
            break
        latest = chunk[-1]['cursor']
    completion = plan['completion']
    answer = bookkeep(completion['capabilityId'], dict(completion['input'], exited=exited, delivery=delivery,
                                                      startedAt=started, latestCursor=latest))
    if not isinstance(answer, dict) or answer.get('status') != 'COMPLETED':
        sys.stderr.write('[sfx-api run %s] completion answered %s\n' % (run.run_id, json.dumps(answer)))
        run.finish()
        return
    run.end()
    if plan.get('published') is True:
        channel.append(run, exited, exited.get('at'))
    answer = bookkeep(plan['facts']['capabilityId'], {'execution': run.identity(),
                                                      'events': [event for event, _ in run.events]})
    if not isinstance(answer, dict) or answer.get('status') != 'CAPTURED':
        sys.stderr.write('[sfx-api run %s] facts answered %s\n' % (run.run_id, json.dumps(answer)))
    run.finish()


class Runs:
    """The runs this host has admitted: those executing or waiting, and the declared number of ended ones, kept for
    reconnects until a run's stream replays its retained trace."""

    def __init__(self):
        self.lock = threading.Lock()
        self.runs = {}
        self.pending = queue.Queue()
        self.waiting = 0

    def admit(self, plan):
        """Queue the run the plan names, once: 'queued', 'held' when the facade holds it already, or 'refused' when the
        declared queue has no room, and that run then ends with the declared delivery answer."""
        bound = settings['runs']['queue']
        with self.lock:
            if plan['runId'] in self.runs:
                return 'held'
            run = self.runs[plan['runId']] = Run(plan)
            ended = [run_id for run_id, known in self.runs.items() if known.finished]
            for run_id in ended[:max(0, len(ended) - settings['runs']['retainedEnded'])]:
                del self.runs[run_id]
            refused = self.waiting >= bound['waiting']
            if not refused:
                self.waiting += 1
        run.note({'kind': 'admitted', 'at': now()})
        if refused:
            threading.Thread(target=finish, args=(run, bound['delivery'], None, None), daemon=True).start()
            return 'refused'
        self.pending.put(run)
        return 'queued'

    def get(self, run_id):
        with self.lock:
            return self.runs.get(run_id)

    def work(self, kernel):
        while True:
            run = self.pending.get()
            with self.lock:
                self.waiting -= 1
            started = now()
            if kernel.process is None or kernel.process.poll() is not None:
                kernel.start()
            run.note({'kind': 'started', 'at': started, 'pid': kernel.process.pid})
            envelope = run.plan['envelope']
            ref = (envelope.get('observation') or {}).get('ref')
            kernel.expected[ref] = run
            delivery = kernel.deliver(envelope)
            closing = kernel.capture(envelope)
            kernel.expected.pop(ref, None)
            finish(run, delivery, closing, started)


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


class Session:
    """A stream's session as its directive declares it: its expiry, and its recheck at the declared interval."""

    def __init__(self, declared):
        declared = declared if isinstance(declared, dict) else {}
        self.declared_expiry = declared.get('expiresAt')
        self.expires = instant(self.declared_expiry)
        recheck = declared.get('recheck')
        interval = recheck.get('intervalMilliseconds') if isinstance(recheck, dict) else None
        self.recheck = recheck if isinstance(interval, int) and interval > 0 else None
        self.checked = time.monotonic()

    def unreadable(self):
        """Whether the directive declares an expiry the facade cannot read: the session ends at once."""
        return self.declared_expiry is not None and self.expires is None

    def wait(self, longest):
        if self.recheck:
            longest = min(longest, self.recheck['intervalMilliseconds'] / 1000 - (time.monotonic() - self.checked))
        if self.expires:
            longest = min(longest, (self.expires - datetime.datetime.now(datetime.timezone.utc)).total_seconds())
        return longest

    def ended(self):
        """Whether the session has expired, or its recheck, when due, cannot confirm it."""
        if self.expires and datetime.datetime.now(datetime.timezone.utc) >= self.expires:
            return True
        if self.recheck and time.monotonic() - self.checked >= self.recheck['intervalMilliseconds'] / 1000:
            if not sessions.live(self.recheck):
                return True
            self.checked = time.monotonic()
        return False


class Sessions:
    """The declared session recheck of open streams, its answer shared for one interval by the streams of one recheck
    input when the recheck declares it shared."""

    def __init__(self):
        self.lock = threading.Lock()
        self.checked = {}

    def live(self, recheck):
        shared = recheck.get('shared') is True
        key = json.dumps(recheck.get('input'), sort_keys=True)
        interval = recheck['intervalMilliseconds'] / 1000
        if shared:
            with self.lock:
                at, answer = self.checked.get(key, (None, None))
                if at is not None and time.monotonic() - at < interval:
                    return answer
        outcome = bookkeep(recheck['capabilityId'], recheck.get('input'))
        answer = isinstance(outcome, dict) and outcome.get('status') == 'LIVE'
        if shared:
            with self.lock:
                self.checked[key] = (time.monotonic(), answer)
        return answer


def choose(select, started):
    """The run window the subscription's select capability chooses from the retained windows, or None; and whether its
    delivery answered."""
    outcome = bookkeep(select['capabilityId'], {
        'select': {'run': select.get('run'), 'graphId': select.get('graphId')},
        'windows': channel.retained_windows(), 'started': started})
    if outcome is None:
        return None, False
    window = outcome.get('window') if isinstance(outcome, dict) else None
    return (window if isinstance(window, dict) and isinstance(window.get('runId'), str) else None), True


class Channel:
    """The estate's live observation channel: every event this host publishes, in one sequence within the declared
    bounds, read by every subscriber. An event's position is reserved when it is written; the publish capability frames
    each batch of queued events, in position order, on a kernel of its own, and the channel keeps each frame exactly as
    answered, with the run window it names. It keeps the retained run windows as the answered window effects describe
    them: a window opens, takes the graphs it names, and closes."""

    def __init__(self, publisher):
        self.instance = str(uuid.uuid4())
        self.changed = threading.Condition()
        self.pending = collections.deque()
        self.frames = collections.deque()
        self.windows = []
        self.reserved = 0
        self.published = 0
        self.bytes = 0
        self.publisher = publisher

    def append(self, execution, event, received):
        """Reserve the event's position and queue it for publishing; the position. An event of no execution, such as a
        drawing change, has none."""
        with self.changed:
            self.reserved += 1
            self.pending.append((self.reserved, execution, event, received))
            self.changed.notify_all()
            return self.reserved

    def settled(self, positions, timeout):
        """Whether the channel published every one of the positions with a frame, waiting up to the timeout for it to
        publish them."""
        deadline = time.monotonic() + timeout
        with self.changed:
            while self.published < max(positions) and time.monotonic() < deadline:
                self.changed.wait(deadline - time.monotonic())
            framed = {frame[0] for frame in self.frames if frame[0] in positions and frame[1]}
            return framed == set(positions)

    def latest(self):
        with self.changed:
            return self.reserved

    def publish(self):
        """Publish the queued events in position order, each batch the queued events within the declared bounds. A batch
        the capability does not answer position by position has empty frames, and its positions are a gap."""
        declared = settings['channel']
        while True:
            with self.changed:
                while not self.pending:
                    self.changed.wait()
                batch, size = [], 0
                while self.pending and len(batch) < declared['batchEvents']:
                    length = len(json.dumps(self.pending[0][2], separators=(',', ':')).encode('utf-8'))
                    if batch and size + length > declared['batchBytes']:
                        break
                    batch.append(self.pending.popleft())
                    size += length
            answer = invoke(self.publisher, declared['publish']['capabilityId'], {
                'channel': self.instance,
                'events': [dict({'seq': seq, 'receivedAt': received, 'event': event},
                                **({'execution': execution.identity()} if execution else {}))
                           for seq, execution, event, received in batch]})
            publications = answer.get('publications') if isinstance(answer, dict) else None
            if not (isinstance(publications, list) and len(publications) == len(batch)
                    and all(isinstance(each, dict) and each.get('seq') == seq and isinstance(each.get('frame'), str)
                            for each, (seq, _, _, _) in zip(publications, batch))):
                sys.stderr.write('[sfx-api channel] events %d..%d were not published: %s\n' % (
                    batch[0][0], batch[-1][0], json.dumps(answer)))
                publications = [{'seq': seq, 'frame': ''} for seq, _, _, _ in batch]
            with self.changed:
                for each in publications:
                    effect = each.get('window') if isinstance(each.get('window'), dict) else {}
                    run_id = effect.get('runId') if isinstance(effect.get('runId'), str) else None
                    length = len(each['frame'].encode('utf-8'))
                    self.frames.append((each['seq'], each['frame'], length, run_id, effect.get('opens') is True))
                    self.bytes += length
                    if run_id is None:
                        continue
                    if effect.get('opens') is True:
                        self.windows.append({'runId': run_id, 'startSeq': each['seq'], 'endSeq': None, 'graphs': []})
                    elif effect.get('closes') is True or 'graph' in effect:
                        window = next((window for window in reversed(self.windows) if window['runId'] == run_id), None)
                        if window is not None and window['endSeq'] is None:
                            if effect.get('closes') is True:
                                window['endSeq'] = each['seq']
                            else:
                                window['graphs'].append(effect['graph'])
                self.published = batch[-1][0]
                while len(self.frames) > declared['retainedFrames'] or self.bytes > declared['retainedBytes']:
                    self.bytes -= self.frames.popleft()[2]
                while (self.windows and self.windows[0]['endSeq'] is not None and self.frames
                       and self.windows[0]['endSeq'] < self.frames[0][0]):
                    self.windows.pop(0)
                self.changed.notify_all()

    def retained_windows(self):
        """The retained run windows, newest first, as the select capability takes them."""
        with self.changed:
            return [dict(window, graphs=list(window['graphs'])) for window in reversed(self.windows)]

    def after(self, cursor, timeout):
        """The published frames after the cursor, as (position, frame, length, window, opens), waiting up to the timeout
        for one."""
        with self.changed:
            if self.published <= cursor:
                self.changed.wait(timeout)
            first = self.frames[0][0] if self.frames else self.published + 1
            return list(itertools.islice(self.frames, max(0, cursor + 1 - first), None))


class Drawings:
    """The estate's circuit drawing changes, on the kernel the host's bookkeeping shares. The declared read capability,
    invoked at the declared interval with the cursor it answered last, answers the channel events of the drawings that
    changed and what to read from next, and the facade appends each event as answered. The cursor advances only once the
    channel has published every one of them, so a failed publication is read again, and an unsettled pass is read on at
    once."""

    def __init__(self, kernel):
        self.kernel = kernel
        self.cursor = None

    def watch(self):
        declared = settings['drawings']
        interval = declared['intervalMilliseconds'] / 1000
        while True:
            answer = bookkeep(declared['capabilityId'], {'cursor': self.cursor, 'limit': declared['limit']})
            if not (isinstance(answer, dict) and answer.get('status') == 'READ' and isinstance(answer.get('events'), list)):
                sys.stderr.write('[sfx-api drawings] %s answered %s\n' % (declared['capabilityId'], json.dumps(answer)))
                time.sleep(interval)
                continue
            received = now()
            positions = [channel.append(None, event, received) for event in answer['events']]
            if positions and not channel.settled(positions, self.kernel.kind['answerTimeoutMs'] / 1000):
                sys.stderr.write('[sfx-api drawings] changes at %d..%d were not published; reading them again\n' % (
                    positions[0], positions[-1]))
                time.sleep(interval)
                continue
            cursor = answer.get('cursor') or {}
            if cursor.get('version') != (self.cursor or {}).get('version') or answer.get('reads'):
                sys.stderr.write('[sfx-api drawings] %s version %s: %d drawings read, %d changes published, settled %s%s\n' % (
                    'watching from' if self.cursor is None else 'read to', cursor.get('version'), answer.get('reads') or 0,
                    len(positions), bool(answer.get('settled')), ', full pass' if answer.get('fullPass') else ''))
            self.cursor = cursor
            if not answer.get('settled'):
                continue
            time.sleep(interval)


def carried(answer):
    """Whether the declared settings are ones this facade carries out: every member it acts on is there, request
    executions are not published, and the kernel's observation queue keeps its defaults."""
    try:
        request, runs_, channel_, drawings = answer['request'], answer['runs'], answer['channel'], answer['drawings']
        return (answer['contractId'] == 'api-host-configuration.v1'
                and isinstance(request['envelope'].get('request'), dict) and isinstance(request['waitMilliseconds'], int)
                and isinstance(request['busy'], str) and isinstance(request['failure'], str)
                and all(isinstance(runs_['events'][key], int) for key in ('maxEvents', 'wholeObservationBytes'))
                and all(isinstance(runs_['trace'][key], int) for key in ('chunkBytes', 'chunkEvents'))
                and isinstance(runs_['queue']['waiting'], int) and isinstance(runs_['queue']['refusal'], str)
                and isinstance(runs_['queue']['delivery'], dict) and isinstance(runs_['retainedEnded'], int)
                and isinstance(answer['streams']['keepaliveMilliseconds'], int)
                and isinstance(channel_['publish']['capabilityId'], str)
                and all(isinstance(channel_[key], int) for key in ('retainedFrames', 'retainedBytes', 'batchEvents', 'batchBytes'))
                and channel_['requests']['published'] is False
                and isinstance(drawings['capabilityId'], str)
                and isinstance(drawings['intervalMilliseconds'], int) and isinstance(drawings['limit'], int)
                and answer['observationQueue'] is None)
    except (KeyError, TypeError, AttributeError):
        return False


def plan_carried(plan):
    """Whether an execute-run plan is one this facade carries out: a run, its envelope, and its events, trace,
    completion and facts capabilities, none of which the facade publishes."""
    if not (isinstance(plan, dict) and isinstance(plan.get('runId'), str) and isinstance(plan.get('envelope'), dict)
            and isinstance(plan['envelope'].get('request'), dict)):
        return False
    steps = [plan.get(step) for step in ('events', 'trace', 'completion', 'facts')]
    return (all(isinstance(step, dict) and isinstance(step.get('capabilityId'), str) and step.get('published') is False
                for step in steps)
            and isinstance(plan['completion'].get('input'), dict))


def stream_carried(directive):
    stream = directive.get('stream')
    after = directive.get('after')
    return (isinstance(directive.get('runId'), str) and isinstance(after, int) and after >= 0 and isinstance(stream, dict)
            and all(isinstance(stream.get(frame), str) for frame in ('head', 'open', 'keepalive', 'sessionEnded', 'end')))


def subscription_carried(directive):
    after, frames, select = directive.get('after'), directive.get('frames'), directive.get('select')
    return (isinstance(directive.get('head'), str) and (after is None or isinstance(after, int) and after >= 0)
            and directive.get('beyondLatest') == 'replay-retained'
            and (frames is None or isinstance(frames, dict) and all(isinstance(value, str) for value in frames.values()))
            and (select is None or isinstance(select, dict) and isinstance(select.get('capabilityId'), str)))


def closes(response):
    """Whether a response's head says Connection: close."""
    head = response.partition('\r\n\r\n')[0]
    return any(name.strip().lower() == 'connection' and value.strip().lower() == 'close'
               for name, _, value in (line.partition(':') for line in head.split('\r\n')[1:]))


class Facade(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def __getattr__(self, name):
        # Every method reaches the ingress, whatever it is.
        if name.startswith('do_'):
            return self.answer
        raise AttributeError(name)

    def answer(self):
        raw = (self.raw_requestline + str(self.headers).encode('latin-1')
               + self.rfile.read(int(self.headers.get('content-length', 0)))).decode('utf-8', 'replace')
        try:
            kernel = kernels.get(timeout=settings['request']['waitMilliseconds'] / 1000)
        except queue.Empty:
            return self.write(settings['request']['busy'])
        envelope = copy.deepcopy(settings['request']['envelope'])
        # The host owns request admission identity. It is never read from a
        # client header/body, and travels with this one kernel delivery.
        request_id = str(uuid.uuid4())
        envelope['request']['input'] = {
            'contractId': 'serve-http-request-request.v1', 'raw': raw,
            'requestExecutionId': request_id, 'executionPath': 'request',
        }
        try:
            delivery = kernel.deliver(envelope)
        finally:
            kernels.put(kernel)
        response = ((delivery.get('outcome') or {}).get('result') or {}).get('outcome')
        if not isinstance(response, str):
            return self.write(settings['request']['failure'])
        head, _, body = response.partition('\r\n\r\n')
        types = [value.strip() for name, _, value in (line.partition(':') for line in head.split('\r\n')[1:])
                 if name.strip().lower() == 'content-type']
        if types != [DIRECTIVE]:
            return self.write(response)
        try:
            directive = json.loads(body)
        except ValueError:
            directive = None
        kind = directive.get('directive') if isinstance(directive, dict) else None
        if not isinstance(directive, dict) or directive.get('contractId') != CONTRACT:
            return self.refuse(directive, 'not ' + CONTRACT)
        if kind == 'stream-run':
            return self.stream(directive) if stream_carried(directive) else self.refuse(directive, 'stream-run')
        if kind == 'stream-estate':
            return self.subscribe(directive) if subscription_carried(directive) else self.refuse(directive, 'stream-estate')
        written = (directive.get('respond') or {}).get('raw') if isinstance(directive.get('respond'), dict) else None
        if kind not in ('execute-run', 'respond') or not isinstance(written, str):
            return self.refuse(directive, str(kind))
        if kind == 'execute-run':
            if not plan_carried(directive.get('run')):
                return self.refuse(directive, 'execute-run')
            if runs.admit(directive['run']) == 'refused':
                return self.write(settings['runs']['queue']['refusal'])
        self.write(written)

    def write(self, response):
        """Write a response exactly as declared, and close the connection when it says so."""
        self.wfile.write(response.encode('utf-8'))
        self.wfile.flush()
        if closes(response):
            self.close_connection = True

    def refuse(self, directive, reason):
        """A directive the facade cannot carry out: the host log names it, and the client receives the declared failure."""
        named = {key: directive.get(key) for key in ('contractId', 'directive')} if isinstance(directive, dict) else directive
        sys.stderr.write('[sfx-api directive] refused (%s): %s\n' % (reason, json.dumps(named)))
        self.write(settings['request']['failure'])

    def stream(self, directive):
        """Server-sent events of a run, each frame as run.events answered it, ended with the run's end frame once its
        completion is stored, with the declared end frame for a run the facade does not hold, or with the declared session
        end at the caller session's expiry or the first declared recheck that cannot confirm it."""
        self.close_connection = True
        stream, cursor = directive['stream'], directive['after']
        run = runs.get(directive['runId'])
        session = Session(directive.get('session'))
        keepalive = settings['streams']['keepaliveMilliseconds'] / 1000
        try:
            self.wfile.write((stream['head'] + stream['open']).encode('utf-8'))
            self.wfile.flush()
            if run is None:
                self.wfile.write(stream['end'].encode('utf-8'))
                self.wfile.flush()
                return
            if session.unreadable():
                return self.session_ended(stream, cursor)
            wrote = time.monotonic()
            while True:
                events, ended = run.after(cursor, max(0.05, session.wait(keepalive - (time.monotonic() - wrote))))
                if events:
                    cursor = events[-1][0]['cursor']
                    self.wfile.write(''.join(frame for _, frame in events).encode('utf-8'))
                    wrote = time.monotonic()
                elif not ended and time.monotonic() - wrote >= keepalive:
                    self.wfile.write(stream['keepalive'].encode('utf-8'))
                    wrote = time.monotonic()
                self.wfile.flush()
                if ended:
                    self.wfile.write(run.end_frame.encode('utf-8'))
                    self.wfile.flush()
                    return
                if session.ended():
                    return self.session_ended(stream, cursor)
        except ConnectionError:
            return

    def session_ended(self, stream, cursor):
        self.wfile.write(stream['sessionEnded'].replace('{cursor}', str(cursor)).encode('utf-8'))
        self.wfile.flush()

    def subscribe(self, directive):
        """Server-sent frames of the channel: the declared head and opening, the published frames after the declared
        cursor (every retained frame when it is beyond the latest position; none without one) and the declared replay end,
        then each frame as it is published, the declared keep-alive frame while it is quiet, and the declared end frame at
        the caller session's expiry or the first declared recheck that cannot confirm the session; it closes at the
        declared bound. With a run selection only the chosen run window's frames are written: the directive's select
        capability chooses it from the retained windows, and chooses again each time a window opens while none is chosen;
        a selection whose delivery fails ends the subscription. Only the frames the directive declares are written."""
        self.close_connection = True
        frames, select, after = directive.get('frames') or {}, directive.get('select'), directive.get('after')
        session = Session(directive.get('session'))
        bound = directive.get('bound')
        ends = time.monotonic() + bound if isinstance(bound, int) and bound > 0 else None
        keepalive = settings['streams']['keepaliveMilliseconds'] / 1000
        state = {'window': None, 'failed': False}
        if select:
            state['window'], answered = choose(select, None)
            state['failed'] = not answered

        def selected(published):
            if not select:
                return ''.join(frame for _, frame, _, _, _ in published)
            kept = []
            for position, frame, _, run_id, opens in published:
                if state['window'] is None and opens and not state['failed']:
                    state['window'], answered = choose(select, position)
                    state['failed'] = not answered
                if state['window'] is not None and run_id == state['window']['runId']:
                    kept.append(frame)
            return ''.join(kept)
        try:
            self.wfile.write((directive['head'].replace('{instance}', channel.instance)
                              + frames.get('open', '')).encode('utf-8'))
            self.wfile.flush()
            if state['failed']:
                return
            if session.unreadable():
                self.wfile.write(frames.get('sessionEnded', '').encode('utf-8'))
                self.wfile.flush()
                return
            latest = channel.latest()
            if after is None:
                cursor = latest
            else:
                start = 0 if after > latest else after
                published = channel.after(start, 0)
                self.wfile.write(selected(published).encode('utf-8'))
                cursor = published[-1][0] if published else min(after, latest)
            self.wfile.write(frames.get('replayComplete', '').encode('utf-8'))
            self.wfile.flush()
            wrote = time.monotonic()
            while not state['failed']:
                wait = session.wait(keepalive - (time.monotonic() - wrote))
                if ends:
                    wait = min(wait, ends - time.monotonic())
                published = channel.after(cursor, max(0.05, wait))
                text = selected(published) if published else ''
                if published:
                    cursor = published[-1][0]
                if text:
                    self.wfile.write(text.encode('utf-8'))
                    wrote = time.monotonic()
                elif time.monotonic() - wrote >= keepalive:
                    self.wfile.write(frames.get('keepalive', '').encode('utf-8'))
                    wrote = time.monotonic()
                self.wfile.flush()
                if session.ended():
                    self.wfile.write(frames.get('sessionEnded', '').encode('utf-8'))
                    self.wfile.flush()
                    return
                if ends and time.monotonic() >= ends:
                    return
        except ConnectionError:
            return


def admit(kernel, answers, index):
    """The declared settings as the kernel answers them, which admits the host's bundle in that kernel."""
    answers[index] = invoke(kernel, SETTINGS, {})


every = {kind: [Kernel(host[kind]) for _ in range(host[kind]['instances'])]
         for kind in ('kernel', 'workers', 'publisher', 'drawings')}
if len(every['publisher']) != 1 or len(every['drawings']) != 1:
    sys.exit('[sfx-api] the channel has one publisher and one drawing reader')
started = every['kernel'] + every['publisher'] + every['drawings']
answers = [None] * len(started)
admissions = [threading.Thread(target=admit, args=(kernel, answers, index)) for index, kernel in enumerate(started)]
for admission in admissions:
    admission.start()
for admission in admissions:
    admission.join()
if not all(isinstance(answer, dict) for answer in answers):
    sys.exit('[sfx-api] a kernel did not answer %s; the host does not listen' % SETTINGS)
settings = answers[0]
if not carried(settings):
    sys.exit('[sfx-api] %s answered settings this facade does not carry out: %s' % (SETTINGS, json.dumps(settings)))
kernels = queue.Queue()
for kernel in every['kernel']:
    kernels.put(kernel)
bookkeepers = queue.Queue()
bookkeepers.put(every['drawings'][0])
sessions = Sessions()
channel = Channel(every['publisher'][0])
threading.Thread(target=channel.publish, daemon=True).start()
runs = Runs()
for kernel in every['workers']:
    threading.Thread(target=runs.work, args=(kernel,), daemon=True).start()
threading.Thread(target=Drawings(every['drawings'][0]).watch, daemon=True).start()
http.server.ThreadingHTTPServer((host['http']['host'], host['http']['port']), Facade).serve_forever()
