// npm install --prefix .tmp/hosted-client ajv@8.17.1 ajv-formats@3.0.1 esbuild@0.25.12
// node tools/build-hosted-client-validators.cjs <sfx-platform>/clients/api
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const deps = path.join(root, '.tmp/hosted-client/node_modules');
const Ajv = require(path.join(deps, 'ajv/dist/2020')).default;
const standalone = require(path.join(deps, 'ajv/dist/standalone')).default;
const ajv = new Ajv({ strict: false, code: { source: true }, allErrors: false });
require(path.join(deps, 'ajv-formats'))(ajv);
const names = {
  profile: 'hosted-execution-profile.v1', request: 'hosted-execution-acceptance-request.v1',
  receipt: 'hosted-execution-acceptance.v1', error: 'hosted-execution-invocation-error.v1',
  readRequest: 'hosted-execution-acceptance-read-request.v1', readResult: 'hosted-execution-acceptance-read-result.v1',
  proof: 'hosted-execution-delivery-proof.v1', context: 'hosted-execution-acceptance-context.v1'
};
for (const name of Object.values(names)) ajv.addSchema(JSON.parse(fs.readFileSync(path.join(root, 'contracts', name + '.schema.json'))));
const target = path.resolve(process.argv[2]);
const temporary = path.join(root, '.tmp/hosted-client/generated.cjs');
fs.writeFileSync(temporary, standalone(ajv, Object.fromEntries(Object.entries(names).map(([k, v]) => [k, v + '.schema.json']))));
require(path.join(deps, 'esbuild')).buildSync({ entryPoints: [temporary], bundle: true, platform: 'node', format: 'cjs',
  minify: true, outfile: path.join(target, 'hosted-validators.cjs'), banner: { js: '// Generated from sfx-api contracts by tools/build-hosted-client-validators.cjs; Ajv 8.17.1, ajv-formats 3.0.1.' } });
