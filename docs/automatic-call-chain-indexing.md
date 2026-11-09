# Automatic call-chain indexing

Status: implementation record; subordinate to the product SLA in sfx-platform.

`append-api-run-trace` in the packaged bundle hid the estate's revised trace
writer. Updating its database document therefore had no effect on execution.
The kernel image also holds a pinned v1 encoding program; updating the estate's
provider catalogue did not change that program.

The repair removes the packaged capability document and its manifest entry,
allowing the existing resolver to read the estate. The document is deleted so
the release builder's directory scan cannot bring it back. The deployed v2
encoder carries the original event text as `nativeEvents` in its existing result.
The estate binds `sfx-api-run-trace-encode-port.v2` and consumes that field in
the existing trace-append SQL invocation. The identity database owns the derived
index and the `evidence.inspect_run_call_chain @run_id` reader.

This is a one-time API packaging contribution, not an estate-only delivery. It
adds no kernel implementation, capability invocation, model call or domain rule.
Further projection changes remain in identity SQL and estate declarations.

Maintained tools:

- `tools/unbundle-estate-capability.py`: remove the named document and repin
  the manifest, preserving unrelated documents; replay leaves the same bytes.
- `tools/project-trace-encoder.py`: carry the source events in the existing
  deployed v2 encoding program.
- `deploy/estate-trace-projection.Dockerfile`: apply those changes as a forward
  layer over an exact deployed image, preserving unrelated released work.

The staging repair used original image `sha256:0f0cb1b4da32d95d258df8a5d7e7568fc80b3abb84acf88663e8a34936800110`.
ACR builds `cabx` and `caby` produced final image
`sha256:2567c3d684551fce0b3ae41fdf8332a4451779dbdfe5981fd0bcf4db606d0e0b`,
selected on `sfx-api-test` in resource group `sidefx_group`.

Live run `4d33ac6b-9338-3ff8-ba72-bd42dffda673` used the revised encoder and
was automatically indexed. Read-only verification run
`74ec9cfd-b78a-ca05-5c44-8cc8d1a96a52` compared its call chain against the
independently decoded source. Verification
`29cc31e5-901e-bb7e-2a0b-8b2043c090fd` reproduced all 14 rows of the owner's
historical MSFT run. Verification `4f6129b7-4cff-be25-4c98-424bf02fd001`
also passed for a retained failed run with zero nested calls.

Full receipts, maintained identity/estate SQL, migration checkpoints and the
independent verifier are under `sfx-platform/tools/run-inspection/`.
