#!/usr/bin/env bash
# Installs this provider; the logic lives in ../common/deploy.sh.
# Run as run_user (sudo is invoked internally).
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec bash "$HERE/../common/deploy.sh" "$HERE"
