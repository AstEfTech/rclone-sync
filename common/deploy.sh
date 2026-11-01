#!/usr/bin/env bash
# Installs the script and systemd units using the settings from .env.
# Run as RUN_USER (sudo is invoked internally).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

if [ ! -f "$HERE/.env" ]; then
  echo "Missing $HERE/.env: cp .env.example .env and fill it in" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Copies without CR: files may have reached the Pi from Windows with CRLF
strip_cr() { sed 's/\r$//' "$1" > "$2"; }

strip_cr "$HERE/.env" "$TMP_DIR/env"
set -a
# shellcheck source=/dev/null
. "$TMP_DIR/env"
set +a

for var in RUN_USER SRC_REMOTE DST_DIR MOUNT_POINT APP_DIR; do
  if [ -z "${!var:-}" ]; then
    echo "$var is not set in $HERE/.env" >&2
    exit 1
  fi
done

if [ "$(id -un)" != "$RUN_USER" ]; then
  echo "Run as user $RUN_USER (not via sudo)" >&2
  exit 1
fi

case "$DST_DIR/" in
  "${MOUNT_POINT%/}"/*) ;;
  *) echo "DST_DIR ($DST_DIR) must be inside MOUNT_POINT ($MOUNT_POINT)" >&2; exit 1 ;;
esac

if ! command -v rclone >/dev/null 2>&1; then
  echo "rclone is not installed."
  if [ ! -t 0 ]; then
    echo "Install it (curl https://rclone.org/install.sh | sudo bash) and rerun deploy.sh" >&2
    exit 1
  fi
  read -r -p "Install rclone now via https://rclone.org/install.sh (needs sudo)? [y/N] " answer
  case "$answer" in
    [yY]|[yY][eE][sS]) curl -fsSL https://rclone.org/install.sh | sudo bash ;;
    *) echo "Aborted: rclone is required" >&2; exit 1 ;;
  esac
  command -v rclone >/dev/null 2>&1 || { echo "rclone installation failed" >&2; exit 1; }
fi

REMOTE_NAME="${SRC_REMOTE%%:*}:"
if ! rclone listremotes | grep -qxF "$REMOTE_NAME"; then
  echo "rclone remote '$REMOTE_NAME' not found for user $RUN_USER." >&2
  echo "Configure it first: see gdrive/CONNECTION_README.md" >&2
  exit 1
fi

mkdir -p "$APP_DIR/log"
strip_cr "$HERE/scripts/gdrive-pull.sh" "$TMP_DIR/gdrive-pull.sh"
strip_cr "$HERE/scripts/watch-log.sh" "$TMP_DIR/watch-log.sh"
strip_cr "$HERE/system/gdrive-pull.timer" "$TMP_DIR/gdrive-pull.timer"
strip_cr "$HERE/system/gdrive-pull.service.in" "$TMP_DIR/gdrive-pull.service.in"

install -m 755 "$TMP_DIR/gdrive-pull.sh" "$APP_DIR/gdrive-pull.sh"
install -m 755 "$TMP_DIR/watch-log.sh" "$APP_DIR/watch-log.sh"
install -m 600 "$TMP_DIR/env" "$APP_DIR/.env"

sed -e "s|@RUN_USER@|$RUN_USER|g" \
    -e "s|@APP_DIR@|$APP_DIR|g" \
    -e "s|@MOUNT_POINT@|$MOUNT_POINT|g" \
    "$TMP_DIR/gdrive-pull.service.in" > "$TMP_DIR/gdrive-pull.service"

sudo install -m 644 "$TMP_DIR/gdrive-pull.service" /etc/systemd/system/gdrive-pull.service
sudo install -m 644 "$TMP_DIR/gdrive-pull.timer" /etc/systemd/system/gdrive-pull.timer
sudo systemctl daemon-reload
sudo systemctl enable --now gdrive-pull.timer

systemctl list-timers | grep gdrive || true
