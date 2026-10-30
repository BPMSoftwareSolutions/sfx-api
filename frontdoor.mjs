// sfx-api frontdoor: serves the declared API. Operations come from the interface
// authority row (sidefx-api-interface.v1); each request runs its declared
// capability through the installed kernel over sfx-command-delivery.v1.
// Node built-ins only.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { createHash, timingSafeEqual } from 'node:crypto';

const configFile = process.env.SFX_API_CONFIG ?? new URL('./sfx-api.config.json', import.meta.url);
const config = JSON.parse(fs.readFileSync(configFile, 'utf8'));
const port = Number(process.env.PORT ?? config.port ?? 8796);
const token = process.env.SFX_API_TOKEN ?? null;
const kernelDir = process.env.SFX_KERNEL_DIR
  ?? path.join(process.env.LOCALAPPDATA ?? path.join(process.env.HOME ?? '.', '.local/share'), 'sfx', 'kernel', config.kernel.digest);
const kernelEntry = path.join(kernelDir, process.env.SFX_KERNEL_ENTRY ?? config.kernel.entryPoint);

// Fill the declared envelope template: a string equal to "{{name}}" becomes the value.
const fill = (template, values) => Array.isArray(template) ? template.map(item => fill(item, values))
  : template && typeof template === 'object' ? Object.fromEntries(Object.entries(template).map(([key, value]) => [key, fill(value, values)]))
  : typeof template === 'string' && /^\{\{\w+\}\}$/.test(template) ? values[template.slice(2, -2)] : template;

// One kernel process per invocation: the envelope on stdin, the result JSON on stdout.
function invoke(capabilityId, input, { namespace = 'sidefx:capabilities', timeoutMilliseconds = config.kernel.timeoutMilliseconds } = {}) {
  return new Promise(resolve => {
    const envelope = fill(config.kernel.envelope, { capabilityId, namespace, input: JSON.stringify(input ?? {}) });
    const child = spawn(kernelEntry, config.kernel.args, { cwd: kernelDir, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    const out = [], err = [];
    const timer = setTimeout(() => { child.kill('SIGKILL'); finish({ error: { code: 'RUN_TIMEOUT', message: `Run exceeded ${timeoutMilliseconds} ms.` } }); }, timeoutMilliseconds);
    let done = false;
    function finish(result) { if (done) return; done = true; clearTimeout(timer); resolve(result); }
    child.stdout.on('data', chunk => out.push(chunk));
    child.stderr.on('data', chunk => { if (err.length < 64) err.push(chunk); });
    child.on('error', error => finish({ error: { code: 'KERNEL_START_FAILED', message: error.message } }));
    child.on('close', code => {
      const text = Buffer.concat(out).toString('utf8'), at = text.indexOf('{');
      try { finish(at < 0 ? { error: { code: 'KERNEL_OUTPUT_UNAVAILABLE', message: `Kernel exited ${code} without output.` } } : { result: JSON.parse(text.slice(at)) }); }
      catch { finish({ error: { code: 'KERNEL_OUTPUT_INVALID', message: `Kernel exited ${code} with output that is not JSON.` } }); }
    });
    child.stdin.end(JSON.stringify(envelope));
  });
}

// The declared operations, read from the interface authority row and refreshed.
let operations = [], authorityDigest = null, loadedAt = null;
async function loadAuthority() {
  const { namespace, id, loader } = config.authority;
  const { result, error } = await invoke(loader, { namespace_id: namespace, declared_id: id });
  const body = result?.rows?.[0]?.body;
  if (error || !body) throw new Error(`AUTHORITY_UNAVAILABLE: ${error?.code ?? 'no selected definition'}`);
  const semantics = JSON.parse(body).semantics ?? {};
  operations = (semantics.operations ?? []).map(operation => {
    const method = String(operation.method ?? operation.route?.method ?? 'GET').toUpperCase();
    const template = operation.path ?? operation.route?.path;
    const names = [];
    const pattern = new RegExp('^' + String(template).replace(/[.*+?^$()|[\]\\]/g, '\\$&')
      .replace(/\\?\{(\w+)\\?\}/g, (_, name) => { names.push(name); return '([^/]+)'; }) + '/?$');
    return { ...operation, method, template, pattern, names,
      capabilityId: operation.capabilityId ?? operation.capability?.id,
      namespace: operation.namespace ?? operation.capability?.namespace ?? 'sidefx:capabilities' };
  }).filter(operation => operation.template && operation.capabilityId);
  authorityDigest = createHash('sha256').update(body).digest('hex');
  loadedAt = new Date().toISOString();
}

const send = (response, status, body) => {
  response.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  response.end(JSON.stringify(body));
};
const authorized = request => {
  if (!token) return true;
  const given = Buffer.from(String(request.headers.authorization ?? '')), expected = Buffer.from(`Bearer ${token}`);
  return given.length === expected.length && timingSafeEqual(given, expected);
};
const readBody = request => new Promise((resolve, reject) => {
  const chunks = []; let size = 0;
  request.on('data', chunk => { size += chunk.length; if (size > config.maximumRequestBytes) { reject(new Error('REQUEST_TOO_LARGE')); request.destroy(); } else chunks.push(chunk); });
  request.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
  request.on('error', reject);
});

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url, 'http://frontdoor');
  if (url.pathname === '/healthz') return send(response, operations.length ? 200 : 503,
    { ready: operations.length > 0, operations: operations.length, authority: config.authority.id, authorityDigest, loadedAt });
  if (!authorized(request)) return send(response, 401, { error: { code: 'UNAUTHORIZED', message: 'A valid bearer token is required.' } });
  for (const operation of operations) {
    const match = request.method === operation.method && url.pathname.match(operation.pattern);
    if (!match) continue;
    let input = Object.fromEntries(url.searchParams);
    operation.names.forEach((name, index) => { input[name] = decodeURIComponent(match[index + 1]); });
    if (!['GET', 'HEAD'].includes(request.method)) {
      try { const text = await readBody(request); if (text.trim()) input = { ...input, ...JSON.parse(text) }; }
      catch (error) { return send(response, 400, { error: { code: error.message === 'REQUEST_TOO_LARGE' ? 'REQUEST_TOO_LARGE' : 'REQUEST_BODY_INVALID', message: 'The request body must be one JSON object.' } }); }
    }
    const { result, error } = await invoke(operation.capabilityId, input,
      { namespace: operation.namespace, timeoutMilliseconds: operation.timeoutMilliseconds ?? config.kernel.timeoutMilliseconds });
    return error ? send(response, 502, { error }) : send(response, 200, result);
  }
  send(response, 404, { error: { code: 'OPERATION_NOT_DECLARED', message: `${request.method} ${url.pathname} is not a declared operation.` } });
});

try { await loadAuthority(); } catch (error) { console.error(error.message); }
setInterval(() => loadAuthority().catch(error => console.error(error.message)), config.authority.refreshMilliseconds).unref();
server.listen(port, () => console.log(`sfx-api frontdoor on :${port}, ${operations.length} declared operations`));
