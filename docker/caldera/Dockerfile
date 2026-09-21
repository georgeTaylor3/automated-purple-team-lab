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

EXPOSE 8888 7010 7011 7012 2222 8022

CMD ["/opt/caldera/venv/bin/python3", "server.py", "--insecure"]
