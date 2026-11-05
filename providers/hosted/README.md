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

Version 5 removes the separate acceptance credential. The ingress provider wraps
the existing declared parser and retains only a canonical Authorization bearer
for the acceptance POST. The bearer is outside graph values, bound to the host's
request UUID, available once for at most the request lifetime, and registered
with kernel observation redaction. A later ingress clears any unused value.
The coordinator validates the same operator session through HTTPS and passes it
to its bounded probe process; no vault read, sign-in, renewal or storage occurs.
Duplicate headers, another request UUID and replay cannot release a credential.

Records are stored on the deployment's persistent `/home` mount. `coordinator.lock`
is an OS-held exclusive lock; process death releases it. `active.json` identifies
its current attempt. A surviving RUNNING record without matching live ownership
is UNKNOWN, and is never resubmitted. Terminal JSON is flushed to a new file and
atomically renamed. A write failure prevents a successful response.
