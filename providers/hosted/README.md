The host module implements the declared HTTP acceptance and record ports. The
port configuration owns the operator binding, probe plan, receipt expression,
record directory and observation program. The kernel remains unchanged.

Build against the exact deployed kernel artifact:

```powershell
& 'C:/Program Files/dotnet/dotnet.exe' run --project providers/hosted/tests/Tests.csproj -c Release "-p:KernelRoot=<artifact directory>" -- C:/lab/repos/sfx-api
python -B contracts/validate-hosted-execution-receipt.py .tmp/projected-receipt.json
python -B -m unittest discover -s providers/hosted/tests -p 'test_*.py' -v
./tools/prepare-hosted-image.ps1 -KernelRoot <artifact directory> -Destination <new context directory>
```

The provider tests exercise synthetic receipts, declared ingress and dispatch,
cross-process admission, process death and retained readback. They do not claim
live acceptance. `tools/build-hosted-release.py` deterministically projects the
sources and pins the capability documents and provider authority. Image assembly
verifies those bytes again after copying them to the build context.

The pinned kernel's schema adapter does not implement `unevaluatedProperties`
or asserted date-time formats. The provider therefore validates the complete
receipt with the published Python validator and pinned JSON Schema dependencies
before terminal persistence. Kernel carrier schemas are not substituted for that
validation. The client independently uses generated Ajv validators from the same
schema files and reconciles identities and original artifact bytes.

Credential diagnostics distinguish a value that does not match the deployed
ingress's session-bearer format from a correctly shaped value rejected by session
authentication. The check occurs inside the host's credential-consuming program.
It returns only a typed failure and a fixed message, with no value, prefix, length
or hash of the credential. `CREDENTIAL_STORED` remains a storage receipt.

Records are stored on the deployment's persistent `/home` mount. `coordinator.lock`
is an OS-held exclusive lock; process death releases it. `active.json` identifies
its current attempt. A surviving RUNNING record without matching live ownership
is UNKNOWN, and is never resubmitted. Terminal JSON is flushed to a new file and
atomically renamed. A write failure prevents a successful response.
