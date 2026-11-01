#!/usr/bin/env bash
# Removes the integration of one provider installed by deploy.sh: stops and removes
# the systemd timer and service, deletes $app_dir/<NAME>-pull/ (script, settings, logs).
# NOT touched: files already copied to dst_dir, the rclone remote and rclone.conf,
# config.yml, rclone itself.
# Not run directly: <provider>/undeploy.sh calls it with the provider directory.
# Run as run_user (sudo is invoked internally). -y skips the confirmation.
set -euo pipefail

COMMON="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
HERE="$(cd "${1:?Usage: undeploy.sh <provider dir> [-y]}" && pwd)"
ASSUME_YES=0
[ "${2:-}" = "-y" ] && ASSUME_YES=1

# shellcheck source=config.sh
. "$COMMON/config.sh"
cfg_load "$COMMON/../config.yml"   # tells where the provider is installed

NAME="$(provider_name "$HERE")"
if [ -z "$NAME" ]; then
  echo "NAME is not set in $HERE/provider.conf" >&2
  exit 1
fi

RUN_USER="$(cfg run_user)"
APP_DIR="$(cfg app_dir)"
for pair in "RUN_USER:$RUN_USER" "APP_DIR:$APP_DIR"; do
  if [ -z "${pair#*:}" ]; then
    echo "${pair%%:*} is not set in config.yml (common or providers.$NAME)" >&2
    exit 1
  fi
done

if [ "$(id -un)" != "$RUN_USER" ]; then
  echo "Run as user $RUN_USER (not via sudo)" >&2
  exit 1
fi

INSTALL_DIR="$APP_DIR/$NAME-pull"
UNITS=("/etc/systemd/system/$NAME-pull.timer" "/etc/systemd/system/$NAME-pull.service")

# Sanity guard before any rm -rf: the directory must look like our installation
if [ -d "$INSTALL_DIR" ] && [ ! -f "$INSTALL_DIR/provider.conf" ]; then
  echo "$INSTALL_DIR has no provider.conf: not an installation made by deploy.sh, leaving it alone" >&2
  exit 1
fi

echo "Will remove integration '$NAME':"
for f in "${UNITS[@]}"; do [ -e "$f" ] && echo "  $f"; done
[ -d "$INSTALL_DIR" ] && echo "  $INSTALL_DIR (script, settings, logs)"
echo "Files already copied to the destination are kept."
if [ "$ASSUME_YES" != 1 ]; then
  if [ ! -t 0 ]; then
    echo "Not a terminal: pass -y to confirm" >&2
    exit 1
  fi
  read -r -p "Continue? [y/N] " answer
  case "$answer" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted"; exit 1 ;;
  esac
fi

# Timer first, so no new run starts; then stop a run that is in progress
sudo systemctl disable --now "$NAME-pull.timer" 2>/dev/null || true
sudo systemctl stop "$NAME-pull.service" 2>/dev/null || true

if [ -d "$INSTALL_DIR" ]; then
  # A run started by hand (not by systemd) still holds the same lock as pull.sh
  exec 8>"$INSTALL_DIR/.lock"
  if ! flock -n 8; then
    echo "$NAME-pull is still running (manual run?): finish it and rerun undeploy.sh" >&2
    exit 1
  fi
  rm -rf "$INSTALL_DIR"
fi

sudo rm -f "${UNITS[@]}"
sudo systemctl daemon-reload
sudo systemctl reset-failed "$NAME-pull.service" "$NAME-pull.timer" 2>/dev/null || true

echo "Integration '$NAME' removed."
