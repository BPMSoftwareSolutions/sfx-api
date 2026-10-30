// sfx-api frontdoor: HTTP transport only. Every request is handed to the declared
// request resolver, a capability the kernel resolves from rows, over
// sfx-command-delivery.v1; the resolver's outcome is the response. Routing,
// operations and shaping are rows, never code here. Node built-ins only.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { timingSafeEqual } from 'node:crypto';

const config = JSON.parse(fs.readFileSync(process.env.SFX_API_CONFIG ?? new URL('./sfx-api.config.json', import.meta.url), 'utf8'));
const port = Number(process.env.PORT ?? config.port);
const token = process.env.SFX_API_TOKEN ?? null;
const kernelDir = process.env.SFX_KERNEL_DIR
  ?? path.join(process.env.LOCALAPPDATA ?? path.join(process.env.HOME ?? '.', '.local/share'), 'sfx', 'kernel', config.kernel.digest);
const kernelEntry = path.join(kernelDir, process.env.SFX_KERNEL_ENTRY ?? config.kernel.entryPoint);

// The envelope is configuration: a string equal to "{{name}}" takes the value.
const fill = (template, values) => template && typeof template === 'object'
  ? Object.fromEntries(Object.entries(template).map(([key, value]) => [key, fill(value, values)]))
  : typeof template === 'string' && /^\{\{\w+\}\}$/.test(template) ? values[template.slice(2, -2)] : template;

function resolve(request) {
  return new Promise(done => {
    const child = spawn(kernelEntry, config.kernel.args, { cwd: kernelDir, windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'] });
    const out = [];
    const timer = setTimeout(() => child.kill('SIGKILL'), config.kernel.timeoutMilliseconds);
    child.stdout.on('data', chunk => out.push(chunk));
    child.on('error', error => { clearTimeout(timer); done({ disposition: 'failed', error: { code: 'KERNEL_START_FAILED', message: error.message } }); });
    child.on('close', () => {
      clearTimeout(timer);
      const text = Buffer.concat(out).toString('utf8');
      try { done(JSON.parse(text.slice(text.indexOf('{')))); }
      catch { done({ disposition: 'failed', error: { code: 'KERNEL_OUTPUT_UNAVAILABLE', message: 'The kernel answered no JSON.' } }); }
    });
    child.stdin.end(JSON.stringify(fill(config.kernel.envelope, { capabilityId: config.resolver, input: JSON.stringify(request) })));
  });
}

const authorized = request => {
  if (!token) return true;
  const given = Buffer.from(String(request.headers.authorization ?? '')), expected = Buffer.from(`Bearer ${token}`);
  return given.length === expected.length && timingSafeEqual(given, expected);
};

http.createServer((request, response) => {
  const chunks = [];
  request.on('data', chunk => chunks.push(chunk));
  request.on('end', async () => {
    if (!authorized(request)) {
      response.writeHead(401, { 'content-type': 'application/json' });
      return response.end(JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'A valid bearer token is required.' } }));
    }
    const url = new URL(request.url, 'http://frontdoor');
    const output = await resolve({ method: request.method, path: url.pathname, query: Object.fromEntries(url.searchParams),
      body: Buffer.concat(chunks).toString('utf8') });
    // The resolver's declared outcome (api-response.v1) is the response; a failed run is a 502 with the kernel's error.
    const run = output.outcome?.result, answer = run?.disposition === 'completed' ? run.outcome : null;
    response.writeHead(answer ? answer.status : 502, { 'content-type': 'application/json; charset=utf-8', ...answer?.headers });
    response.end(answer ? (typeof answer.body === 'string' ? answer.body : JSON.stringify(answer.body))
      : JSON.stringify({ error: run?.error ?? output.error ?? { code: output.errorCode ?? 'RUN_FAILED', message: 'The run did not complete.' } }));
  });
}).listen(port, () => console.log(`sfx-api frontdoor on :${port}; resolver ${config.resolver}`));
