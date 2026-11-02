# DRAFT for owner approval, 2026-11-01. Nothing in this feature is built until it is approved.

Feature: Credentials stored on the hosted API survive restarts
  A key stored with store-credential on sfx-api-test stays stored when the container restarts, whether a deploy or
  App Service restarts it.

  User story: As the owner, I want a key I store on the hosted API to stay stored across deploys and restarts, so that
  OV3 and every capability that reads it keep working without my storing it again.

  How it emerged: deploy/start.sh writes vault.json from the App Service setting SFX_CREDENTIAL_VAULT_B64 at every
  start, into the container's own filesystem, and store-credential writes into that same file. The container has no
  persistent storage, so every restart loses the keys stored since the last start. The deploy of sfx-api 1ac2d0f
  (2026-11-02 01:31 UTC) lost DEEPSEEK_API_KEY and TYPESAFE_AI_API_KEY, and OV3 failed until they were stored again.
  Every earlier deploy did the same.

  Recommended: the vault directory alone lives on an Azure Files share mounted into the container, and the setting
  only seeds an empty share. App Service's own persistent /home storage is not used: it would mount over the image's
  /home, where the host and the kernel live.

  The option kept open: store-credential writes the sealed vault back to the Key Vault secret behind the setting, so the
  setting stays the one source. That is a change to the estate's vault provider, outside sfx-api.

  Background:
    Given the hosted API https://sfx-api-test.azurewebsites.net

  Scenario: A stored key survives a restart
    Given store-credential stored a probe entry with a non-secret value
    When sfx-api-test restarts
    Then the probe entry still opens with the same value

  Scenario: Only the vault directory is durable
    Then /home/sjones/.local/share/sfx/vault is an Azure Files share mounted into the container
    And the host, the kernel and the key record still come from the image and the settings at every start

  Scenario: The setting seeds an empty vault only
    When the container starts and the share has no vault.json
    Then start.sh writes vault.json from SFX_CREDENTIAL_VAULT_B64
    And when the share already has vault.json, start.sh leaves it unchanged

  Scenario: The vault still opens after the move
    Then the estate database credential opens as it does today
