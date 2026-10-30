# sfx-api

The declared API, deployed by itself. One file, `frontdoor.mjs`, Node built-ins only.

- **Operations are rows.** At boot, and every five minutes after, the frontdoor reads the
  interface authority `sidefx:authorities/sidefx-api-interface.v1` through the kernel. Each
  declared operation maps a method and path to the capability it runs.
- **Execution is the installed kernel.** Every request runs its capability through
  `KernelEntry` (admitted by digest in `sfx-api.config.json`) over `sfx-command-delivery.v1`.
  The envelope template is configuration, not code.
- **Nothing else.** No frontend, no circuit host, no desktop, no browser suites.

## Run

```
node frontdoor.mjs
```

| Setting | Default |
| --- | --- |
| `PORT` | `8796` |
| `SFX_API_TOKEN` | unset: no bearer check (set it everywhere but a developer machine) |
| `SFX_KERNEL_DIR` | `%LOCALAPPDATA%\sfx\kernel\<digest>` |
| `SFX_KERNEL_ENTRY` | `KernelEntry.exe` |
| `SFX_API_CONFIG` | `./sfx-api.config.json` |

`GET /healthz` reports readiness, the number of declared operations and the authority digest.
Any other path is a declared operation or `404 OPERATION_NOT_DECLARED`.
