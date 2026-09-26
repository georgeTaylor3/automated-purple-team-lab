#!/usr/bin/env bash
set -euo pipefail

# Runs as root -- the image's default user, deliberately unchanged --
# specifically so it can fix ownership of the mounted volumes below.
# These are attached by docker-compose at container START, overlaying
# whatever the image had at that path -- meaning the Dockerfile's own
# build-time chown (which only affects the image's baked-in
# filesystem layer) never actually touches them. Without this fix,
# the non-root caldera user below would get a permission error the
# moment it tried to write into either mounted volume.
chown -R caldera:caldera /opt/caldera/data /opt/caldera/conf

# Drop from root to the caldera user for the actual, real process.
# gosu is purpose-built for exactly this hand-off -- avoids su's
# known issues with signal handling and TTY allocation inside
# containers. "$@" is whatever the Dockerfile's CMD supplied, passed
# through unchanged.
exec gosu caldera "$@"
