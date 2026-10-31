#!/usr/bin/env python3
"""The sfx-api hosting facade.

The platform's HTTP server receives a request; the facade hands it, as the raw text the platform
read, to a resident kernel as one sfx-command-delivery.v1 envelope invoking the declared capability
serve-http-request, and writes back the raw HTTP response the kernel resolves. Every mechanic of the
API is declared and resolved by the kernel: the request target, query and body, the credential carrier
and its session digest, the operation, the caller, the run, refusals and the response itself. The
kernels keep running between requests (--resident-envelopes: one envelope per line on stdin, one
delivery per line on stdout), so no request pays a kernel start. The kernel command, the pool size,
the answer bound and the envelope's request are host data in sfx-api.config.json. Python standard
library only: nothing is installed or built.

    python3 host/serve.py sfx-api.config.json
"""
import http.server
import json
import queue
import subprocess
import sys
import threading

host = json.load(open(sys.argv[1], encoding='utf-8'))


class Kernel:
    """One resident kernel, started on first use and again after it exits or overruns the bound."""

    process = None

    def answer(self, raw):
        if self.process is None or self.process.poll() is not None:
            self.process = subprocess.Popen(host['kernel']['command'], cwd=host['kernel']['root'],
                                            stdin=subprocess.PIPE, stdout=subprocess.PIPE)
            self.lines = queue.Queue()
            threading.Thread(target=self.read, args=(self.process.stdout, self.lines), daemon=True).start()
        envelope = {'deliveryType': 'sfx-command-delivery.v1', 'operation': 'invoke',
                    'request': dict(host['request'], input=raw)}
        self.process.stdin.write(json.dumps(envelope, separators=(',', ':')).encode('utf-8') + b'\n')
        self.process.stdin.flush()
        try:
            line = self.lines.get(timeout=host['kernel']['answerTimeoutMs'] / 1000)
        except queue.Empty:
            line = b''
        if not line:
            self.process.kill()
            self.process = None
        return json.loads(line)['outcome']['result']['outcome']

    @staticmethod
    def read(stdout, lines):
        for line in stdout:
            lines.put(line)
        lines.put(b'')


kernels = queue.Queue()
for _ in range(host['kernel']['instances']):
    kernels.put(Kernel())


class Facade(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def answer(self):
        raw = (self.raw_requestline + str(self.headers).encode('latin-1')
               + self.rfile.read(int(self.headers.get('content-length', 0)))).decode('utf-8', 'replace')
        kernel = kernels.get()
        try:
            self.wfile.write(kernel.answer(raw).encode('utf-8'))
        finally:
            kernels.put(kernel)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = answer


http.server.ThreadingHTTPServer((host['http']['host'], host['http']['port']), Facade).serve_forever()
