#!/bin/sh
# Container start: the host facts the estate's declared vault providers read, then the host.
# The sealed vault, its key record and its key come from App Service settings (Key Vault references),
# never from the image. The key goes into a session gnome-keyring with an empty-password login keyring
# that lives only in this container, under the reference the providers declare.
set -eu
: "${SFX_CREDENTIAL_VAULT_B64:?SFX_CREDENTIAL_VAULT_B64 is required}"
: "${SFX_CREDENTIAL_VAULT_KEY_RECORD_B64:?SFX_CREDENTIAL_VAULT_KEY_RECORD_B64 is required}"
: "${SFX_CREDENTIAL_VAULT_KEY:?SFX_CREDENTIAL_VAULT_KEY is required}"
umask 077
mkdir -p "$HOME/.local/share/sfx/vault" "$HOME/.local/share/sfx/credential-vault-keys"
printf '%s' "$SFX_CREDENTIAL_VAULT_B64" | base64 -d > "$HOME/.local/share/sfx/vault/vault.json"
printf '%s' "$SFX_CREDENTIAL_VAULT_KEY_RECORD_B64" | base64 -d > "$HOME/.local/share/sfx/credential-vault-keys/0f2fb3b502843c274efcadf4856f631a.json"
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS
# An empty line creates/unlocks the login collection; EOF alone leaves it absent.
printf '\n' | gnome-keyring-daemon --unlock --components=secrets >/dev/null
gnome-keyring-daemon --start --components=secrets >/dev/null
printf '%s' "$SFX_CREDENTIAL_VAULT_KEY" | secret-tool store --label sfx-credential-vault service sfx-credential-vault key 0f2fb3b502843c274efcadf4856f631a
unset SFX_CREDENTIAL_VAULT_B64 SFX_CREDENTIAL_VAULT_KEY_RECORD_B64 SFX_CREDENTIAL_VAULT_KEY
exec python3 host/serve.py sfx-api.config.json
