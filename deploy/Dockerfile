# The sfx-api deployment: the host, the admitted kernel and the host facts the estate's declared vault
# providers read (user sjones, HOME /home/sjones, secret-tool over gnome-keyring). The image holds no
# credential material: start.sh writes the sealed vault, its key record and its key from App Service
# settings (Key Vault references) at start. Build context: this directory with host/,
# sfx-api.config.json and the kernel install under kernel/ (see README, Deploying).
FROM python:3.12-slim-bookworm
RUN apt-get update \
 && apt-get install -y --no-install-recommends gnome-keyring libsecret-tools dbus dbus-x11 ca-certificates libicu72 libssl3 libgssapi-krb5-2 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 1000 sjones
ARG KERNEL_DIGEST
USER sjones
ENV HOME=/home/sjones
# Create writable bootstrap directories before COPY creates root-owned parent paths.
RUN mkdir -p "$HOME/.local/share/sfx/vault" "$HOME/.local/share/sfx/credential-vault-keys"
COPY --chown=sjones:sjones kernel/ /home/sjones/.local/share/sfx/kernel/${KERNEL_DIGEST}/
COPY --chown=sjones:sjones host/ /home/sjones/sfx-api/host/
COPY --chown=sjones:sjones sfx-api.config.json start.sh /home/sjones/sfx-api/
RUN chmod 0755 /home/sjones/sfx-api/start.sh /home/sjones/.local/share/sfx/kernel/${KERNEL_DIGEST}/KernelEntry
WORKDIR /home/sjones/sfx-api
EXPOSE 8787
ENTRYPOINT ["/home/sjones/sfx-api/start.sh"]
