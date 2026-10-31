#!/usr/bin/env python3
"""The sfx-api hosting facade.

The platform's HTTP server receives a request; the facade hands it, as the raw text the platform
read, to one kernel invocation of the declared capability serve-http-request, and writes back the
raw HTTP response the kernel resolves. Every mechanic of the API is declared and resolved by the
kernel: the request target, query and body, the credential carrier and its session digest, the
operation, the caller, the run, refusals and the response itself. The kernel command is host data
in sfx-api.config.json. Python standard library only: nothing is installed or built.

    python3 host/serve.py sfx-api.config.json
"""
import http.server
import json
import subprocess
import sys

host = json.load(open(sys.argv[1], encoding='utf-8'))


class Facade(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def answer(self):
        self.wfile.write(json.loads(subprocess.run(
            host['kernel']['command'], cwd=host['kernel']['root'], stdout=subprocess.PIPE,
            input=self.raw_requestline + str(self.headers).encode('latin-1')
            + self.rfile.read(int(self.headers.get('content-length', 0)))).stdout).encode('utf-8'))

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = answer


http.server.ThreadingHTTPServer((host['http']['host'], host['http']['port']), Facade).serve_forever()
