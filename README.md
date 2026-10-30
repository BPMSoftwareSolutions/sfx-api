# sfx-api

The declared API, deployed by itself. `frontdoor.mjs` is HTTP transport only: Node built-ins,
no mechanics.

- **Every request goes to one declared resolver.** The frontdoor hands `{method, path, query, body}`
  to the capability named `resolver` in `sfx-api.config.json` (`resolve-api-request`), run by the
  installed kernel over `sfx-command-delivery.v1`. The resolver's outcome (`api-response.v1`:
  `status`, `headers`, `body`) is the response.
- **Routing is rows.** Which operation a request means, its input and the capability it runs are
  declared in `sidefx:authorities/sidefx-api-interface.v1` and resolved by the resolver
  capability, never by code here.
- **The kernel is admitted by digest.** `kernel.digest` selects the installed `KernelEntry`; the
  envelope template is configuration.

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
