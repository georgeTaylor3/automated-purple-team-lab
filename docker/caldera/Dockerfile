# Dockerfile
#
# CALDERA control node, containerized. Same install sequence proven
# working in archive/packer-caldera-control-vm/caldera-control.pkr.hcl --
# same repo, same pinned Go/Node versions, same reasoning for each.
#
# CALDERA_VERSION is the git ref to build from (tag or branch).
# GO_VERSION / NODE_VERSION are pinned explicitly, same reasoning as the
# VM build: apt/base-image versions lag behind what CALDERA's tooling
# requires (Go 1.24+, Node 20.19+/22.12+).

ARG CALDERA_VERSION=master
ARG GO_VERSION=1.27.0
ARG NODE_VERSION=22

FROM ubuntu:24.04

ARG CALDERA_VERSION
ARG GO_VERSION
ARG NODE_VERSION

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        git \
        curl \
        ca-certificates \
        gnupg \
        unzip \
        upx-ucl \
        gosu \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSL -o /tmp/go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm -f /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

RUN git clone --recursive --branch "${CALDERA_VERSION}" \
        https://github.com/apache/caldera.git /opt/caldera

WORKDIR /opt/caldera

RUN python3 -m venv /opt/caldera/venv \
    && /opt/caldera/venv/bin/pip install --upgrade pip \
    && /opt/caldera/venv/bin/pip install -r requirements.txt

# One-time UI build. Runs in the foreground (unlike the VM build's
# background-and-kill approach) so a real failure actually surfaces
# instead of being silently swallowed -- timeout gives it 180s to
# finish and complete its own shutdown, then the explicit `test -d`
# check fails the whole image build if the UI assets don't actually
# exist afterward, rather than reporting a false success like the
# first attempt at this Dockerfile did.
RUN timeout 180s /opt/caldera/venv/bin/python3 server.py --insecure --build; \
    test -d /opt/caldera/plugins/magma/dist

# Non-root execution -- CIS Docker Benchmark, NIST SP 800-190, and
# AC-6 (Least Privilege). Every RUN step above genuinely needed root
# (package installs, downloads, the UI build); only the actual
# runtime process needs to drop that privilege. This chown covers
# the image's own baked-in files; the two mounted volumes
# (/opt/caldera/data, /opt/caldera/conf) are handled separately, at
# runtime, by entrypoint.sh -- they're attached by docker-compose
# AFTER this build step runs, so nothing here ever touches them.
#
# UID/GID pinned to 10001, not auto-assigned or left at a low
# "normal account" number. Confirmed by testing: without an explicit
# ID, the system auto-assigned one that happened to numerically
# collide with a real host user account -- containers share the
# host's UID space by default (no user-namespace remapping
# configured), so "container UID 1001" and "host UID 1001" are
# genuinely the same number at the kernel level. 1000 itself was
# already taken by Ubuntu's own default "ubuntu" user baked into the
# 24.04 base image. 10001 is deliberately far outside any plausible
# real human account range on any host this might ever run on.
RUN groupadd --gid 10001 caldera \
    && useradd --uid 10001 --gid caldera --no-create-home --shell /usr/sbin/nologin caldera \
    && chown -R caldera:caldera /opt/caldera

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8888 7010 7011 7012 2222 8022

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/opt/caldera/venv/bin/python3", "server.py", "--fresh"]
