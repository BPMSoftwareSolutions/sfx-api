#!/bin/sh
# Container start: the host facts the estate's declared vault providers read, then the host.
# /home is App Service's persistent storage, so the sealed vault and the keyring kept there survive
# restarts, with every credential stored since, as on the legacy host. The sealed vault comes from an
# App Service setting (a Key Vault reference) only when /home has none; its key record and its key come
# from settings at every start, never from the image. The key goes into a gnome-keyring with an
# empty-password login keyring, under the reference the providers declare.
set -eu
if [ "$(id -u)" = 0 ]; then
  # App Service mounts /home after the image is built: establish the runtime user's directory on that
  # mount, then drop privileges.
  mkdir -p /home/sjones
  chown sjones:sjones /home/sjones
  chmod 700 /home/sjones
  exec runuser -u sjones -- env HOME=/home/sjones "$0"
fi
: "${SFX_CREDENTIAL_VAULT_B64:?SFX_CREDENTIAL_VAULT_B64 is required}"
: "${SFX_CREDENTIAL_VAULT_KEY_RECORD_B64:?SFX_CREDENTIAL_VAULT_KEY_RECORD_B64 is required}"
: "${SFX_CREDENTIAL_VAULT_KEY:?SFX_CREDENTIAL_VAULT_KEY is required}"
umask 077
mkdir -p "$HOME/.local/share/sfx/vault" "$HOME/.local/share/sfx/credential-vault-keys"
if [ ! -s "$HOME/.local/share/sfx/vault/vault.json" ]; then
  printf '%s' "$SFX_CREDENTIAL_VAULT_B64" | base64 -d > "$HOME/.local/share/sfx/vault/vault.json"
fi
printf '%s' "$SFX_CREDENTIAL_VAULT_KEY_RECORD_B64" | base64 -d > "$HOME/.local/share/sfx/credential-vault-keys/0f2fb3b502843c274efcadf4856f631a.json"
# A Unix socket cannot live on the storage share: the session bus and the keyring's control socket go under /tmp.
XDG_RUNTIME_DIR="$(mktemp -d /tmp/sfx-runtime-XXXXXX)"
export XDG_RUNTIME_DIR
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS
# An empty line creates/unlocks the login collection; EOF alone leaves it absent.
printf '\n' | gnome-keyring-daemon --unlock --components=secrets >/dev/null
gnome-keyring-daemon --start --components=secrets >/dev/null
printf '%s' "$SFX_CREDENTIAL_VAULT_KEY" | secret-tool store --label sfx-credential-vault service sfx-credential-vault key 0f2fb3b502843c274efcadf4856f631a
unset SFX_CREDENTIAL_VAULT_B64 SFX_CREDENTIAL_VAULT_KEY_RECORD_B64 SFX_CREDENTIAL_VAULT_KEY
exec python3 /opt/sfx/host/serve.py /opt/sfx/sfx-api.config.json
