# Finish `open-api-session`: estate-native sign-in through the declared API

Everything needed is in this document. Every fact below has been read from the live estate or from
the repositories; do not re-derive them.

## Words used here

Two unrelated things are named `sfx-api` (see the sfx-api README, first section):

- **the declared API**: the repository `C:\lab\repos\sfx-api`, the new SideFX API, deployed as the
  Azure app `sfx-api-test` (`https://sfx-api-test.azurewebsites.net`);
- **the legacy CLI**: the installed `sfx-api` command. It calls the legacy staging host
  (`https://sidefx-staging-fyfhb9gubneqbpaz.eastus2-01.azurewebsites.net`). Every declaration below
  is written through it into the estate database.

The declared API's kernel reads the estate database on every request. A declaration is live in
`sfx-api-test` at once: **no image rebuild and no redeploy are needed for this work.**

## Goal

The owner: *"We need to fully declare authenticate-ide-user so that we can retire login from
sfx-providers. That way, login can be estate-native and invoked naturally via the API."* The new
capability is `open-api-session`, served by the declared API as `POST /sfx/v1/session`.
`authenticate-ide-user` is retired afterwards.

Tracker: project `declared-api-frontdoor`, task `daf-open-api-session` (IN_PROGRESS).

## Authorization

- The owner hands you this document as the instruction to apply every change in it directly, without
  a flight. Record that in the tracker task when you update it.
- Use the owner's user session for every legacy CLI call (`--auth user`). Check it first:

      sfx-api whoami --json

  It must answer `"disposition":"AUTHENTICATED"`. If it does not, stop and ask the owner to run
  `sfx-api login` on this machine. The owner types the password; you never see it.
- Do not use `--auth machine`; it has not been verified for these writers.

## Already done (do not redo)

- **sfx-identity migration 011** (sfx-dal `d340880`, applied):
  - `identity.begin_api_login(@input {realm, identifier, sourceKey})` returns one row: `attemptId`,
    `allowed`, `salt`, `expected` (base64), with a random salt and tag when the verifier cannot be checked;
  - `identity.complete_api_login(@attempt_id, @allowed, @equals, @verifier_hash)` returns one row:
    `disposition` (`AUTHENTICATED`, `AUTHENTICATION_REJECTED` or `THROTTLED`), `sessionId`,
    `principalId`, `expiresAt`;
  - both wrap the five login procedures of 001 unchanged; neither has run end to end yet.
- **DEPENDENCY `sidefx:dependencies/sfx-identity-login`** (definition `c8a852ab`, source
  `providers/sfx-identity-login.dependency.json`), bound on
  `sidefx:capability:run-declared-graph/run-declared-graph-execute`:
  - `open-session`: mechanic `sfx-identity-login-open-port.v1`, PROVIDER `sfx-identity-login-open`
    (`8ea88a7b`). Its cell input: `value` is the connection string the vault open step returns;
    `context.login` is `{realm, identifier, sourceKey}` (sent to SQL as `@input`); `context.password`
    stays in the program. Its output: `disposition`, `sessionId`, `principalId`, `expiresAt`, `token`
    (the token is meaningful only when `AUTHENTICATED`);
  - `derive-tag`: mechanic `sfx-identity-login-derive-port.v1`, PROVIDER `sfx-identity-login-derive`
    (`1c165e92`). Cell input `{password, salt}`, output `{tag}`.
- **Ingress DEPENDENCY `sfx-api-ingress`** (definition `39ffb87e`; PROVIDERs `d06badff`,
  `f07ed911`): `resolve-request` also returns `source` (`X-Client-IP`, else the first
  `X-Forwarded-For` entry, else empty); every response carries `Cache-Control: no-store`.
- Every principal's realm is `sfx-ide-local`. Policy: 5 attempts per account and 25 per source per
  300 s; sessions last 86400 s.

## The legacy CLI helper (PowerShell)

Paste this at the top of each PowerShell call:

```powershell
$bs=[string][char]92
function J($o){ (ConvertTo-Json -InputObject $o -Depth 80 -Compress).Replace($bs+'u0027',"'") }
function Call($cap,$obj){ $j=J $obj; for ($k=1; $k -le 4; $k++) { $o = ($j | sfx-api capability observe $cap --input - --json --auth user --timeout 300 | Out-String); $i=$o.IndexOf('{'); if ($i -ge 0) { $r=$o.Substring($i) | ConvertFrom-Json; if ($r.invocationResult -and $r.invocationResult.result) { $r=$r.invocationResult.result }; return $r } }; throw "NO_RESULT $cap" }
```

It retries the intermittent "Maximum impersonation nesting level exceeded (limit 32)". Build every
input as a PowerShell object, never by reading a file with `Get-Content -Raw` (it hangs
`ConvertTo-Json`); read files with `[IO.File]::ReadAllText`.

## SEJ operators: exact shapes and semantics

Read from the kernel's engine (`SemanticTransformationEngine`). Only these operators are bound on the
graph runner for this work; use no others.

| Operator | Shape | Semantics |
| --- | --- | --- |
| `literal` | `{"op":"literal","value":V}` | `V` as given (any JSON) |
| `path` | `{"op":"path","path":"a.b.0"}` or `{"op":"path","from":"<let binding>","path":"a"}` | Reads the cell input (or a `let` binding) at a dotted path; a number segment indexes an array (`segments.3`); `""` is the whole value; a missing member is `null` |
| `object` | `{"op":"object","fields":{"k":EXPR,...}}` | An object of the evaluated fields |
| `let` | `{"op":"let","bindings":{"a":EXPR,"b":EXPR},"value":EXPR}` | Bindings are evaluated in order; a later binding can read an earlier one with `"from"` |
| `if` | `{"op":"if","when":EXPR,"then":EXPR,"else":EXPR}` | `when` is truthy unless `null`, `false`, `""`, `0`, `[]` or `{}` |
| `equals` | `{"op":"equals","left":EXPR,"right":EXPR}` | Strict: true only for the same kind and value (ordinal strings, numbers, booleans, `null` = `null`). **Refuses an object or array operand** |
| `type` | `{"op":"type","value":EXPR}` | `"object"`, `"array"`, `"string"`, `"number"`, `"boolean"` or `"null"` (also for a missing member) |
| `length` | `{"op":"length","value":EXPR}` | The count of an array or the length of a string. **Refuses anything else** |
| `greater-than` | `{"op":"greater-than","left":EXPR,"right":EXPR}` | Numbers, or ordinal strings |
| `matches` | `{"op":"matches","value":EXPR,"pattern":"<.NET regex>"}` | True only when the pattern matches the **whole** string (culture-invariant, 100 ms timeout). **Refuses a non-string** |
| `lookup` | `{"op":"lookup","value":OBJECT,"path":STRING}` | The member at a dotted key of an object, or `null`; does not index arrays |
| `try-parse-json` | `{"op":"try-parse-json","value":EXPR}` | `{"disposition":"PARSED","value":<parsed>}`, or `{"disposition":"NOT_PARSED","value":null}` |

**A refusal is silent.** An operator that refuses (`equals` on an object, `length` or `matches` on a
non-string) fails the whole expression, and the step then returns its cell input unchanged. So test
`type` first and reach `equals`, `length` and `matches` only inside the branch where the type is right.
A check compares the declared answer, never only that the run completed.

The generic dispatch step (`generic-capability-invocation.v1`) answers
`{executionTarget, disposition, result}`, with the dispatched capability's output at `result`; a
failed nested call puts `{code, message}` at `result`.

## Steps

### 1. Read the precedent chain

`read-flight-plan`'s DSL is retained in the estate. Read it once:

```powershell
$stmt = "SET NOCOUNT ON; SELECT (SELECT TOP (1) CONVERT(nvarchar(max), CONVERT(varchar(max), co.content_bytes) COLLATE Latin1_General_100_BIN2_UTF8) AS source FROM model.capability_dsl_source s JOIN source.content_object co ON co.content_digest = s.content_digest WHERE s.capability_id = N'read-flight-plan' ORDER BY s.capability_dsl_source_pk DESC FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS value;"
(Call 'sql-database-reader' ([ordered]@{dataSource='sfx-estate-database';statement=$stmt;resultColumn='value';input=@{}})).value.source
```

Its four ports, in order, with their exact configurations:

| Port | `platform:` | `config:` |
| --- | --- | --- |
| vault | `sfx-vault-host-read-port.v1` | `{"providerId":"sfx-vault-file-host","dependency":{"objectKind":"DEPENDENCY","namespace":"sidefx:dependencies","id":"sfx-vault-file"}}` |
| credential | `sfx-identity-credential-port.v1` | `{"providerId":"sfx-identity-database-credential","dependency":{"objectKind":"DEPENDENCY","namespace":"sidefx:dependencies","id":"sfx-identity-database"}}` |
| open | `sfx-vault-reference-open-port.v1` | `{"providerId":"sfx-vault-secret-service-reference","dependency":{"objectKind":"DEPENDENCY","namespace":"sidefx:dependencies","id":"sfx-vault-secret-service"}}` |
| store (replace) | the sign-in port below | |

The vault step carries the capability input through the chain as `context`; the open step adds the
connection string as `value`. An inline SEJ step is `platform: sda-authority-transformation-port.v1`
with `config: {"expression": <SEJ expression>}`; the existing SEJ in `declarations/07-serve-http-request.dsl`
shows the operators in use (`if`, `equals`, `object`, `path`, `literal`, `let`, `type`, `length`,
`matches`, `lookup`, `try-parse-json`), and only operators already used there are bound.

### 2. Declare `open-api-session`

Write `declarations/09-open-api-session.dsl` in the declared API repository:

- the three ports of the table, then the sign-in port: `platform: sfx-identity-login-open-port.v1`,
  `config: {"providerId":"sfx-identity-login-open","dependency":{"objectKind":"DEPENDENCY","namespace":"sidefx:dependencies","id":"sfx-identity-login"}}`;
- then an inline SEJ answer step: for `disposition` `AUTHENTICATED`, `{status: AUTHENTICATED,
  tokenType: Bearer, token, sessionId, principalId, expiresAt}`; otherwise `{status: <disposition>}`;
- input contract `open-api-session-request.v1`: an object with `login` (`realm`, `identifier`,
  `sourceKey`, all strings) and `password` (a string of 1 to 1024 characters);
- output contract `open-api-session-result.v1`: an object with `status` and the optional members above.

Declare it:

```powershell
cmd /c "sfx-api capability author --dsl C:\lab\repos\sfx-api\declarations\09-open-api-session.dsl --json --auth user --timeout 280 2>&1"
```

The answer must contain `"disposition":"COMMITTED"`.

### 3. Route sign-in in the ingress

Edit `declarations/07-serve-http-request.dsl`. Sign-in must not go through `serve-api-request`: its
identify and interface stages send the request body to SQL, and the password must never reach SQL.

- **prepare step** (`serve-http-request-prepare`): when `method` is `POST` and `segments` is exactly
  `["", "sfx", "v1", "session"]` (`length` of `segments` is 4, and `segments.1`, `segments.2`,
  `segments.3` equal `sfx`, `v1`, `session`), parse `body` with `try-parse-json` and check, guarding
  each operator by `type` as above:
  - the parse `disposition` is `PARSED` and the parsed `value` has `type` `object`;
  - `identifier` has `type` `string` and `matches` `^(?=.*\S)[^\x00-\x1F\x7F]{1,254}$`;
  - `password` has `type` `string` and `matches` `^[^\x00]{1,1024}$`.

  In JSON the patterns are written `"^(?=.*\\S)[^\\x00-\\x1F\\x7F]{1,254}$"` and `"^[^\\x00]{1,1024}$"`.

  If both pass, dispatch `open-api-session` (`executionTarget`, `executionNamespace sidefx:capabilities`,
  `executionScenario open-api-session`, `inputType json`) with
  `{login: {realm: "sfx-ide-local", identifier, sourceKey: <source, or "unknown" when empty>}, password}`.
  If either fails, dispatch `answer-api-response` with
  `{contractId: api-response.v1, status: 400, headers: {content-type: application/json; charset=utf-8}, body: {status: LOGIN_INPUT_INVALID}}`.
  Every other request keeps the current prepare unchanged.
- **shape step** (`serve-http-request-shape`): an `api-response.v1` result passes as now. For a result
  of `open-api-session` (`executionTarget` equals `open-api-session`), status by `result.status`, read
  with `lookup` on the literal `{"AUTHENTICATED":200,"AUTHENTICATION_REJECTED":401,"THROTTLED":429}`:
  `AUTHENTICATED` 200, `AUTHENTICATION_REJECTED` 401, `THROTTLED` 429, with the result as the body;
  anything else from that route is 503 with the body `{status: IDENTITY_UNAVAILABLE}` and no message.

Declare it, then re-apply its text input (every DSL declaration resets it):

```powershell
cmd /c "sfx-api capability author --dsl C:\lab\repos\sfx-api\declarations\07-serve-http-request.dsl --json --auth user --timeout 280 2>&1"
(Call 'apply-declared-change' ([ordered]@{contractId='declared-change.v1';changeKind='capability-interface-change';payload=[ordered]@{contractId='capability-interface-change.v1';capabilityId='serve-http-request';inputType='text';inputContract='serve-http-request-request.v1';inputPath='raw';verificationCapabilityId='read-capability-details';preflight=[ordered]@{input=[ordered]@{capabilityId='serve-http-request'};expected=[ordered]@{disposition='terminated'}};route=[ordered]@{resolvedDisposition='terminated'}}})).disposition
```

Both must answer `COMMITTED`.

### 4. Record the route in the interface

Add to `authorities/sidefx-api-interface.v1.json` an operation `open-session`, `POST`, path
`/session`, `callers ["anonymous"]`, `resolves {"kind":"ingress","capabilityId":"open-api-session"}`,
`segments {"0":"","1":"sfx","2":"v1","3":"session"}`, meaning "Sign in: served by the ingress, so the
credential never reaches the frontdoor." Declare the file:

```powershell
$interface = [IO.File]::ReadAllText('C:\lab\repos\sfx-api\authorities\sidefx-api-interface.v1.json') | ConvertFrom-Json
(Call 'model-declare-semantic-object' ([ordered]@{object_kind='AUTHORITY';namespace_id='sidefx:authorities';declared_id='sidefx-api-interface.v1';semantics_json=$interface})).status
```

### 5. Check the derivation

Declare a capability `verify-password-derivation` (`declarations/10-verify-password-derivation.dsl`):
an inline SEJ step that produces `{password: "sfx login check OpYAnFIY", salt: "XzV3zhcHfl3N2ArfiSCREw=="}`,
the derive port (`platform: sfx-identity-login-derive-port.v1`,
`config: {"providerId":"sfx-identity-login-derive","dependency":{"objectKind":"DEPENDENCY","namespace":"sidefx:dependencies","id":"sfx-identity-login"}}`),
and an inline SEJ step answering `{status: MATCHES}` when `tag` equals
`9F6e2oJcKYMjMt/RRwS4V6QM3w8LNxmbOYuI/7A/oXY=` and `{status: MISMATCH, tag}` otherwise. The vector
is a throwaway from an independent Argon2id checked against RFC 9106. Its input contract is an empty
object. Run it on WSL (step 6) with `--input '{}'`; it must answer `MATCHES`.

### 6. Test on WSL, then on Azure

From Git Bash (not PowerShell, which adds a byte-order mark), the kernel run for a raw request:

```bash
wsl.exe -d Ubuntu -- bash -s <<'EOF'

cd ~/.local/share/sfx/kernel/9f78e78d16b5da117162e35f9611386f560ddd2c6e12130ef2285d2564372b4b || exit 1
ask() { printf "$1" | ./KernelEntry capability invoke serve-http-request --input - --input-type text --json --config kernel-host.json; echo; }
ask 'POST /sfx/v1/session HTTP/1.1\r\nHost: x\nContent-Type: application/json\n\n{"identifier":"nobody@invalid","password":"not-it"}'
ask 'POST /sfx/v1/session HTTP/1.1\r\nHost: x\nContent-Type: application/json\n\n{"identifier":"","password":"x"}'
ask 'GET /sfx/v1/nope HTTP/1.1\r\nHost: x\n\n'
ask 'GET /sfx/v1/session HTTP/1.1\r\nHost: x\n\n'
printf '{}' | ./KernelEntry capability invoke verify-password-derivation --input - --json --config kernel-host.json
EOF
```

Expected, in order: 401 with `AUTHENTICATION_REJECTED`; 400 `LOGIN_INPUT_INVALID`; 404
`OPERATION_NOT_DECLARED`; 401 `CALLER_REQUIRED`; `MATCHES`. Then the same against Azure (no rebuild):

```bash
curl -s -i -X POST https://sfx-api-test.azurewebsites.net/sfx/v1/session -H 'Content-Type: application/json' -d '{"identifier":"nobody@invalid","password":"not-it"}'
curl -s -i https://sfx-api-test.azurewebsites.net/sfx/v1/nope
```

The owner tests a real sign-in with their own identifier and password. Never ask for or handle the
owner's password or bearer.

### 7. Retire `authenticate-ide-user`

List the declared-change kinds and look for one that retires or removes a capability:

```powershell
$o = ('{"includeDefinitions":false}' | sfx-api capability observe read-harness-authoring-state --input - --json --auth user --timeout 200 | Out-String)
[regex]::Matches($o, '"changeKind":"[^"]+"') | % { $_.Value } | Sort-Object -Unique
```

`authenticate-ide-user` has no scenarios or ports: it is a declared envelope only. If a kind retires
it, apply it and read the capability back. If none does, add a tracker task for the missing writer
and stop there.

### 8. Record

- The declared API's README: sign-in in "Session operations" and the verified results.
- The tracker task, through `project-tracking`:

```powershell
(Call 'apply-declared-change' ([ordered]@{contractId='declared-change.v1';changeKind='project-tracking';payload=[ordered]@{contractId='project-tracking-change.v1';project=[ordered]@{projectId='declared-api-frontdoor'};tasks=@([ordered]@{projectTaskId='daf-open-api-session';status='IN_PROGRESS';statusDescription='<what was declared, the run results, what is open>'});verificationCapabilityId='read-project-tracker';preflight=[ordered]@{input=[ordered]@{changeKind='project-tracking';includeDefinitions=$true};expected=[ordered]@{disposition='terminated'}};route=[ordered]@{resolvedDisposition='terminated'}}})).disposition
```

  The task stays `IN_PROGRESS` until the owner accepts the real sign-in.
- Commit on `main` in `C:\lab\repos\sfx-api` (run `git branch` first; another agent uses `codex/*`
  branches in this working tree), then push.

## Rules

- The password, the stored verifier and the bearer never go to SQL, run input, observations or
  testimony. Never invoke `open-api-session` through the legacy CLI with a real password.
- A provider re-declaration needs `expected_digest`: the current definition digest as bare lowercase hex.
- `begin_api_login` uses INSERT...EXEC inside; do not call it through INSERT...EXEC.

## Done when

`POST /sfx/v1/session` on `sfx-api-test` answers the bearer for a valid sign-in, as tested by the
owner, and 401, 429 or 400 for the refusals; `verify-password-derivation` answers `MATCHES`; every
step runs on declared estate providers; `authenticate-ide-user` is retired or its writer is tracked;
the tracker task reflects the results.
