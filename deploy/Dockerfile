# The sfx-api deployment: the host, the admitted kernel and the host facts the estate's declared vault
# providers read (user sjones, HOME /home/sjones, secret-tool over gnome-keyring). The image holds no
# credential material. The host and the kernel live under /opt/sfx; /home is App Service's persistent
# storage, mounted after the image is built, where start.sh keeps the sealed vault and the keyring so
# that stored credentials survive restarts, as on the legacy host. Build context: this directory with
# host/, sfx-api.config.json, kernel-host.json (from deploy/), providers/host-provider-authority.json,
# authorities/host-bundle/ and the kernel install under kernel/ (see README, Deploying).
FROM python:3.12-slim-bookworm
RUN apt-get update \
 && apt-get install -y --no-install-recommends gnome-keyring libsecret-tools dbus dbus-x11 ca-certificates libicu72 libssl3 libgssapi-krb5-2 util-linux \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 1000 sjones \
 && mkdir -p /opt/sfx \
 && chown sjones:sjones /opt/sfx
ARG KERNEL_DIGEST
COPY --chown=sjones:sjones kernel/ /opt/sfx/kernel/${KERNEL_DIGEST}/
# The kernel's boot configuration is the host's (deploy/kernel-host.json): it names the host's provider authority, which
# binds the declared-read port to answer-host-declared-read over the pinned bundle (answer-host-declared-read.feature).
COPY --chown=sjones:sjones kernel-host.json /opt/sfx/kernel/${KERNEL_DIGEST}/kernel-host.json
COPY --chown=sjones:sjones providers/host-provider-authority.json /opt/sfx/providers/host-provider-authority.json
COPY --chown=sjones:sjones authorities/host-bundle/ /opt/sfx/authorities/host-bundle/
COPY --chown=sjones:sjones host/ /opt/sfx/host/
COPY --chown=sjones:sjones sfx-api.config.json start.sh /opt/sfx/
RUN chmod 0755 /opt/sfx/start.sh /opt/sfx/kernel/${KERNEL_DIGEST}/KernelEntry
WORKDIR /opt/sfx
EXPOSE 8787
# start.sh begins as root to establish the runtime user's directory on the mounted /home, then drops to sjones.
ENTRYPOINT ["/opt/sfx/start.sh"]
