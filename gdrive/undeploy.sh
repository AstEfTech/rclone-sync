#!/usr/bin/env bash
# Removes this provider's integration; the logic lives in ../common/undeploy.sh.
# Run as run_user (sudo is invoked internally). -y skips the confirmation.
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec bash "$HERE/../common/undeploy.sh" "$HERE" "$@"



SRC="gdrive:Media"
DST="/mnt/media_storage/media"
MOUNT="/mnt/media_storage"
MIN_FREE_GB=10
KEEP_LOG_DAYS=14