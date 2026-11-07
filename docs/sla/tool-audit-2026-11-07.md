# Tool audit, 2026-11-07

This repo's rule is that any tool used to build, declare, verify or probe the host's work must itself be a declared
capability. Scratch scripts produce no evidence. This audit lists every tool that has touched sfx-api's evidence or
build, in two places:
- `tools/` in this repo;
- the Claude scratch folders for this workspace, which sit under the user's temp directory at `claude/557cd2d05c8634bd/`.

Each tool is reported as **accounted** (a feature states its behaviour) or **unaccounted** (none does), together with
what it did. Whether to declare, retire or keep each one is the owner's call. This audit decides none of it, and it
changed, ran and deleted nothing.

## Repository tools on main at `ea4b012`

No feature names any of these tools.

| Tool | What it does | Status |
| --- | --- | --- |
| `tools/build-hosted-release.py` | Projects source declarations into the image's bundle. It rewrites `accept-hosted-execution-profile`'s bindings from the profile, the acceptance plan and the provider program, then rebuilds the manifest from `sorted((BUNDLE/'capabilities').glob('*.json'))`. Added in `24e8d51`. That glob re-listed the stale `open-api-session.json`, and the host served a broken sign-in until `ccb82ed` ([signin-outage-2026-11-05](../signin-outage-2026-11-05.md)). | Unaccounted. It generates host declarations that ship in the image. |
| `tools/prepare-hosted-image.ps1` | Builds the image context. It builds the hosted providers, runs the bundle projection and copies the image's inputs. It then verifies each bundle document's digest and the startup manifest pin, and prints the host-files digest. | Unaccounted. Its check is the only verification of the pin before a release, and it is not a declared capability. |
| `tools/build-hosted-client-validators.cjs` | Compiles this repo's eight hosted-execution contracts into standalone Ajv validators. It writes them as `hosted-validators.cjs` into a path it is given, documented as `<sfx-platform>/clients/api`. Its dependencies are installed by hand into `.tmp/hosted-client`. | Unaccounted. It writes a generated artifact into another repository's tree. |
| `tools/invoke-hosted-acceptance.ps1` | A retired entry point. It prints `HOSTED_ACCEPTANCE_PASSWORD_FLOW_RETIRED`, starts no request and exits 3. | Unaccounted, and inert. |
| `tools/build-content-release.py` | "Project the content HTTP declarations into the image-owned bundle." Added in `ea4b012`, where `prepare-hosted-image.ps1` runs it before the bundle projection. It belongs to the content candidate ([change-admission.md](change-admission.md)). | Unaccounted. It generates host declarations that ship in the image. |

## Scratch folders

The workspace has 12 session folders. Eleven hold at most one file. Session `ef076059-6ca0-4e8a-9d69-056608659a3c`
(2026-11-04) holds 1,306 files:
- 23 scripts;
- 6 App Service log downloads (`sfx-logs5` to `sfx-logs10`, 1,245 files, with their zips), not inspected for content;
- 30 command results and inputs (`*.out`, `*.err`, `*.json`, two `.dsl` copies);
- 2 task outputs.

The audit read every script's header and grepped each for its actions. These are source observations, not execution
evidence.

| Script | What it does | What it reached |
| --- | --- | --- |
| `declare-probes.py` | "Declare both probe providers and capabilities in the host's bundle, and re-pin it. Run from the repo root." | It wrote `authorities/host-bundle/`. The probes match `2aaceba` ("declare the probes its checks run on") by name. |
| `declare-acceptance.py` | "Slice 3: declare the acceptance HTTPS provider and accept-hosted-execution-profile, move the profile reader to version 2, route POST /sfx/v1/hosted-execution/acceptance, and re-pin the bundle." | It wrote `authorities/host-bundle/`. It matches `2089ecf` ("…on the request path (slice 3)") by name. `tools/build-hosted-release.py` later took over part of the work; whether it covers every edit was not checked. |
| `declare-operator.py` | Declares `start-hosted-acceptance`, `retain-hosted-acceptance-receipt` and `read-hosted-acceptance-receipt` with their providers, and re-pins the bundle. | None of the three is in the manifest at `f97bd66` or at `ea4b012`. |
| `t4-envelope.py`, `t4-envelope.sh`, `envsize.py` | Replay the T4 run's end to kernel `244e0129` on WSL, ASCII-escaped and as UTF-8, and compute envelope sizes. | The cause recorded in [azure-test-2026-11-04](../azure-test-2026-11-04.md), which calls the replay "a diagnostic, not evidence". |
| `signin-probe.py`, `signin-probe.sh`, `signin-probe-worktree.sh`, `build-hosted-dll.sh` | Stage a revision's provider authority and bundle into a WSL mirror, then deliver `open-api-session` for an identifier no principal has. | The cause recorded in [signin-outage-2026-11-05](../signin-outage-2026-11-05.md). |
| `accept-local.py`, `accept-local.sh`, `admit-guard.py`, `check-reader.py` | Deliver envelopes straight to a resident kernel on WSL: the coordinator's gates and evaluator, run admission's refusal, and the profile reader. | Diagnostics behind the 2026-11-04 slices. |
| `host-probes-wsl.py`, `smoke-probes.sh`, `rehearse-launcher.py`, `client-offhost.sh` | Drafts of the probe program and its launcher, run the way the C# provider starts them. | `host-probes-wsl.py` became `providers/host-probes.py`, which `sfx-api-host-child-process.dependency.json` declares. |
| `hosted-probes.py` | Runs each probe on sfx-api-test through the installed CLI (pinned by path) and judges it against the receipt schema. "A diagnostic of the deployed probes, not an acceptance receipt." | It duplicates the judgement of the coordinator's declared receipt expression. |
| `facade-smoke.sh` | Starts the changed facade in the WSL mirror and sends a few HTTP requests. | A diagnostic. |
| `findcmd.py`, `findcmd2.py`, `findcmd3.py` | Search Claude session transcripts for earlier commands. | Investigation only. |

The `.dsl` and matching `.json` files are read results (`capability-dsl-sources.v1`, `READ`) of the estate's
`http-exchange` and `store-credential` sources. `dep-read.json` is the input of a SQL read of estate definitions. None of
these files records a submission.

## Findings

1. **Host declarations were generated outside the repo.** Three scratch scripts wrote bundle documents and re-pinned
   the manifest. Bundle documents of the same names were then committed and deployed. The generator still in the repo,
   `tools/build-hosted-release.py`, is undeclared, and its directory glob caused the 2026-11-05 outage.
2. **The two recorded causes rest on scratch replays.** Both the T4 loss and the sign-in outage were located by
   delivering envelopes straight to a kernel on WSL. No declared capability can replay a delivery against a staged
   bundle, so neither regression has a declared check. The release probe set
   ([host-sla.md §2](host-sla.md#2-definitions)) catches the sign-in symptom on the deployed host. It does not catch
   the cause before a release.
3. **The image's pin check is undeclared.** `tools/prepare-hosted-image.ps1` is the only place where the bundle's
   digests and the startup pin are verified before a release. The values it prints are part of the host build identity
   ([measurement-contract.md](measurement-contract.md)).
4. **A generated artifact crosses repos.** `tools/build-hosted-client-validators.cjs` writes into sfx-platform's tree.
   Under this workspace's handoff rule, sfx-platform's own session applies anything in its tree.
5. **Nothing here is evidence.** No observation in the [ledger](ledger/) relies on a scratch script's output. Where a
   recorded cause came from one, the observation says so and is unverified.
