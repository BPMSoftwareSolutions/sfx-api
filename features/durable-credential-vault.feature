# Canonical feature of the container's credential vault, 2026-11-02. Every scenario was approved by the owner on
# 2026-11-01 and keeps its words; this write-up adds only the rule, the tags and the comments.
# Tags, terms and the owner's direction are in features/README.md.
# The legacy behaviour it restores: sfx-platform 094951f^, deploy/sda-kernel/README.md "Vault custody and restart",
# deploy/sda-kernel/gateway.mjs (lines 39-45, 69-75) and deploy/sda-kernel/Dockerfile.

@project:sfx-api
@component:container-vault
@status:proposed-for-review
Feature: Credentials stored on the hosted API survive restarts, as on the legacy host
  A key stored with store-credential on sfx-api-test stays stored when the container restarts, whether a deploy or
  App Service restarts it.

  User story: As the owner, I want a key I store on the hosted API to stay stored across deploys and restarts, as it did
  on the legacy host, so that OV3 and every capability that reads it keep working without my storing it again.

  How it was lost: the legacy host kept its encrypted vault and keyring on App Service's persistent /home, restored its
  bootstrap vault only when none was there, and ran its code from /opt/sfx. The sfx-api deploy (a360819, 2026-10-30)
  put the host and the kernel under /home, left persistent storage off, and rewrites vault.json from the setting
  SFX_CREDENTIAL_VAULT_B64 at every start. So every restart loses the keys stored since the last start. The legacy API
  comparison covered the API surface only, not how the host kept its vault. The deploy of sfx-api 1ac2d0f
  (2026-11-02 01:31 UTC) lost DEEPSEEK_API_KEY and TYPESAFE_AI_API_KEY, and every earlier deploy did the same.

  Background:
    Given the hosted API https://sfx-api-test.azurewebsites.net

  Rule: The vault and keyring survive restarts on persistent /home

    @approved:2026-11-01
    @status:unchecked
    Scenario: A stored key survives a restart
      Given store-credential stored a probe entry with a non-secret value
      When sfx-api-test restarts
      Then the probe entry still opens with the same value
      # Built in 07bfc99. No restart run is cited in this repo.

    @approved:2026-11-01
    @status:installed
    Scenario: The vault and keyring live on persistent /home, the code does not
      Then App Service persistent storage is on for /home (WEBSITES_ENABLE_APP_SERVICE_STORAGE true)
      And the host and the kernel are in the image under /opt/sfx, so the /home mount hides neither
      And the keyring's control socket is under /tmp, since a Unix socket cannot live on the storage share
      # deploy/Dockerfile:15-17 put the host and the kernel under /opt/sfx; deploy/start.sh:26-28 put the socket under
      # /tmp. The App Service setting is not in this repo.

    @approved:2026-11-01
    @status:installed
    Scenario: The setting seeds an empty vault only
      When the container starts and /home has no vault.json
      Then start.sh writes vault.json from SFX_CREDENTIAL_VAULT_B64
      And when /home already has vault.json, start.sh leaves it unchanged
      # deploy/start.sh:22-24.

    @approved:2026-11-01
    @status:unchecked
    Scenario: The vault still opens after the move
      Then the estate database credential opens as it does today
