#!/usr/bin/env python3
"""The sfx-api host: native receive and send for the declared API.

It receives an HTTP request, hands it to a resident kernel as one sfx-command-delivery.v1 envelope
for the declared frontdoor, and sends the api-response.v1 the frontdoor answers. Every choice is host
data in sfx-api.config.json; no route, caller, admission or run meaning lives here. Python standard
library only: nothing is installed or built.

    python3 host/serve.py [sfx-api.config.json]
"""
import base64
import hashlib
import json
import os
import queue
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qsl, unquote, urlsplit


# A credential carrier never enters a capability input: no bearer, cookie or verification handle
# reaches run input, cells, events or traces. The caller arrives as a verified trusted context.
CREDENTIAL_HEADERS = frozenset(['authorization', 'proxy-authorization', 'cookie'])


def presented_caller(headers, carriers):
    """The caller a request presents, as a digest only: the credential itself never leaves the host.

    Each declared carrier names where a credential rides (a header with its scheme, or a cookie), how
    it is encoded and how many SHA-256 rounds turn it into the digest the frontdoor resolves.
    """
    for carrier in carriers:
        value = None
        if 'header' in carrier:
            raw = headers.get(carrier['header']) or ''
            prefix = carrier['scheme'] + ' ' if carrier.get('scheme') else ''
            if raw.startswith(prefix):
                value = raw[len(prefix):].strip()
        elif 'cookie' in carrier:
            for pair in (headers.get('cookie') or '').split(';'):
                name, _, content = pair.strip().partition('=')
                if name == carrier['cookie']:
                    value = content
        if not value or carrier.get('encoding') != 'base64':
            continue
        try:
            decoded = base64.b64decode(value, validate=True)
        except ValueError:
            continue
        if len(decoded) != carrier['bytes'] or base64.b64encode(decoded).decode('ascii') != value:
            continue
        digest = decoded
        for _ in range(carrier['digestRounds']):
            digest = hashlib.sha256(digest).digest()
        return {carrier['as']: digest.hex()}
    return None


def load_config(path):
    with open(path, encoding='utf-8') as handle:
        config = json.load(handle)
    kernel = config['kernel']
    kernel['root'] = os.path.expanduser(kernel['root'].replace('{digest}', kernel['digest']))
    return config


class ResidentKernel:
    """One long-lived kernel process: one compact envelope per line on stdin, one result line on stdout."""

    def __init__(self, kernel):
        self.kernel = kernel
        self.process = None
        self.results = None

    def start(self):
        self.process = subprocess.Popen(
            [os.path.join(self.kernel['root'], self.kernel['entryPoint'])] + self.kernel['args'],
            cwd=self.kernel['root'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env=dict(os.environ, **self.kernel.get('environment', {})))
        self.results = queue.Queue()
        threading.Thread(target=self.read_results, args=(self.process, self.results), daemon=True).start()
        threading.Thread(target=self.read_diagnostics, args=(self.process,), daemon=True).start()

    @staticmethod
    def read_results(process, results):
        for line in process.stdout:
            results.put(line)
        results.put(None)

    @staticmethod
    def read_diagnostics(process):
        for line in process.stderr:
            sys.stderr.write('kernel[%d]: %s' % (process.pid, line.decode('utf-8', 'replace')))

    def send(self, envelope, timeout_seconds):
        if self.process is None or self.process.poll() is not None:
            self.start()
        self.process.stdin.write((json.dumps(envelope, separators=(',', ':')) + '\n').encode('utf-8'))
        self.process.stdin.flush()
        try:
            line = self.results.get(timeout=timeout_seconds)
        except queue.Empty:
            self.process.kill()
            self.process = None
            raise TimeoutError('KERNEL_TIMEOUT')
        if line is None:
            self.process = None
            raise RuntimeError('KERNEL_EXITED')
        return json.loads(line)


class Frontdoor:
    """A pool of resident kernels serving the declared frontdoor capability."""

    def __init__(self, config):
        self.capability = config['frontdoor']['capabilityId']
        self.timeout_seconds = config['http']['requestTimeoutMs'] / 1000.0
        self.pool = queue.Queue()
        for _ in range(config['kernel'].get('instances', 1)):
            self.pool.put(ResidentKernel(config['kernel']))

    def answer(self, request):
        envelope = {'deliveryType': 'sfx-command-delivery.v1', 'operation': 'invoke', 'request': {
            'object': 'capability', 'verb': 'invoke', 'subject': self.capability,
            'input': json.dumps(request, separators=(',', ':')), 'inputType': 'json'}}
        kernel = self.pool.get()
        try:
            delivered = kernel.send(envelope, self.timeout_seconds)
        except (TimeoutError, RuntimeError) as failure:
            return refusal(502, str(failure), 'The kernel did not answer the frontdoor envelope.')
        finally:
            self.pool.put(kernel)
        result = (delivered.get('outcome') or {}).get('result') or {}
        response = result.get('outcome') if result.get('disposition') == 'completed' else None
        if not isinstance(response, dict) or response.get('contractId') != 'api-response.v1':
            return refusal(502, 'FRONTDOOR_RESPONSE_INVALID', json.dumps(result.get('error') or result)[:2000])
        return response


def refusal(status, code, message):
    return {'contractId': 'api-response.v1', 'status': status,
            'headers': {'content-type': 'application/json; charset=utf-8'},
            'body': {'error': {'code': code, 'message': message}}}


def handler_for(frontdoor, body_byte_cap, carriers):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def handle_any(self):
            target = urlsplit(self.path)
            length = int(self.headers.get('content-length') or 0)
            if length > body_byte_cap:
                return self.send(refusal(413, 'REQUEST_BYTE_CAP_EXCEEDED', 'The request body exceeds the host bound.'))
            headers = {}
            for name, value in self.headers.items():
                key = name.lower()
                if key in CREDENTIAL_HEADERS:
                    continue
                headers[key] = headers[key] + ', ' + value if key in headers else value
            request = {'method': self.command,
                       'segments': [unquote(segment) for segment in target.path.split('/')],
                       'query': dict(parse_qsl(target.query, keep_blank_values=True)),
                       'headers': headers,
                       'body': self.rfile.read(length).decode('utf-8', 'replace') if length else ''}
            self.send(frontdoor.answer({'request': request, 'caller': presented_caller(self.headers, carriers)}))

        def send(self, response):
            body = response.get('body')
            payload = body.encode('utf-8') if isinstance(body, str) else json.dumps(body, separators=(',', ':')).encode('utf-8')
            self.send_response(int(response.get('status') or 500))
            for name, value in (response.get('headers') or {}).items():
                self.send_header(name, value)
            self.send_header('content-length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = handle_any

        def log_message(self, format, *args):
            sys.stderr.write('%s %s\n' % (self.address_string(), format % args))

    return Handler


def main():
    config = load_config(sys.argv[1] if len(sys.argv) > 1 else 'sfx-api.config.json')
    http = config['http']
    server = ThreadingHTTPServer((http['host'], http['port']),
                                 handler_for(Frontdoor(config), http['bodyByteCap'], config.get('credentialCarriers', [])))
    sys.stderr.write('sfx-api host on %s:%d serving %s\n' % (http['host'], http['port'], config['frontdoor']['capabilityId']))
    server.serve_forever()


if __name__ == '__main__':
    main()
