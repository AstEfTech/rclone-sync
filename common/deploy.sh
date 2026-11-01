#!/usr/bin/env bash
# Installs the script and systemd units for one provider (gdrive, icloud, ...)
# using the provider's provider.conf and the shared .env in the repository root.
# Not run directly: <provider>/deploy.sh calls it with the provider directory.
# Run as RUN_USER (sudo is invoked internally).
set -euo pipefail

COMMON="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
HERE="$(cd "${1:?Usage: deploy.sh <provider dir>}" && pwd)"
ENV_FILE="$COMMON/../.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $(cd "$COMMON/.." && pwd)/.env: cp .env.example .env and fill it in" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Copies without CR: files may have reached the server from Windows with CRLF
strip_cr() { sed 's/\r$//' "$1" > "$2"; }

strip_cr "$HERE/provider.conf" "$TMP_DIR/provider.conf"
# shellcheck source=/dev/null
. "$TMP_DIR/provider.conf"
for var in NAME DESCRIPTION; do
  if [ -z "${!var:-}" ]; then
    echo "$var is not set in $HERE/provider.conf" >&2
    exit 1
  fi
done
PROVIDER="$(basename "$HERE")"

strip_cr "$ENV_FILE" "$TMP_DIR/env"
set -a
# shellcheck source=/dev/null
. "$TMP_DIR/env"
set +a

# Provider variables carry a prefix: gdrive -> GDRIVE_SRC_REMOTE, GDRIVE_DST_DIR
PREFIX="$(echo "$NAME" | tr '[:lower:]' '[:upper:]')_"
SRC_VAR="${PREFIX}SRC_REMOTE"
DST_VAR="${PREFIX}DST_DIR"
SRC_REMOTE="${!SRC_VAR:-}"
DST_DIR="${!DST_VAR:-}"

for var in RUN_USER MOUNT_POINT APP_DIR "$SRC_VAR" "$DST_VAR"; do
  if [ -z "${!var:-}" ]; then
    echo "$var is not set in .env" >&2
    exit 1
  fi
done

if [ "$(id -un)" != "$RUN_USER" ]; then
  echo "Run as user $RUN_USER (not via sudo)" >&2
  exit 1
fi

case "$DST_DIR/" in
  "${MOUNT_POINT%/}"/*) ;;
  *) echo "$DST_VAR ($DST_DIR) must be inside MOUNT_POINT ($MOUNT_POINT)" >&2; exit 1 ;;
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

if [ -n "${MIN_RCLONE_VERSION:-}" ]; then
  RCLONE_VERSION="$(rclone version | head -1 | sed -E 's/^rclone v?//')"
  if [ "$(printf '%s\n' "$MIN_RCLONE_VERSION" "$RCLONE_VERSION" | sort -V | head -1)" != "$MIN_RCLONE_VERSION" ]; then
    echo "rclone $RCLONE_VERSION is too old: $DESCRIPTION needs $MIN_RCLONE_VERSION or newer." >&2
    echo "Update it: curl https://rclone.org/install.sh | sudo bash" >&2
    exit 1
  fi
fi

REMOTE_NAME="${SRC_REMOTE%%:*}:"
if ! rclone listremotes | grep -qxF "$REMOTE_NAME"; then
  echo "rclone remote '$REMOTE_NAME' not found for user $RUN_USER." >&2
  echo "Configure it first: see $PROVIDER/CONNECTION_README.md" >&2
  exit 1
fi

INSTALL_DIR="$APP_DIR/$NAME-pull"
mkdir -p "$INSTALL_DIR/log"
strip_cr "$COMMON/pull.sh" "$TMP_DIR/pull.sh"
strip_cr "$COMMON/watch-log.sh" "$TMP_DIR/watch-log.sh"
strip_cr "$COMMON/pull.timer.in" "$TMP_DIR/pull.timer.in"
strip_cr "$COMMON/pull.service.in" "$TMP_DIR/pull.service.in"

# The installed .env holds only this provider's resolved settings
printf 'SRC_REMOTE=%q\nDST_DIR=%q\nMOUNT_POINT=%q\n' "$SRC_REMOTE" "$DST_DIR" "$MOUNT_POINT" > "$TMP_DIR/app.env"

install -m 755 "$TMP_DIR/pull.sh" "$INSTALL_DIR/$NAME-pull.sh"
install -m 755 "$TMP_DIR/watch-log.sh" "$INSTALL_DIR/watch-log.sh"
install -m 644 "$TMP_DIR/provider.conf" "$INSTALL_DIR/provider.conf"
install -m 600 "$TMP_DIR/app.env" "$INSTALL_DIR/.env"

render() {
  sed -e "s|@NAME@|$NAME|g" \
      -e "s|@DESCRIPTION@|$DESCRIPTION|g" \
      -e "s|@RUN_USER@|$RUN_USER|g" \
      -e "s|@INSTALL_DIR@|$INSTALL_DIR|g" \
      -e "s|@MOUNT_POINT@|$MOUNT_POINT|g" \
      "$1" > "$2"
}
render "$TMP_DIR/pull.service.in" "$TMP_DIR/$NAME-pull.service"
render "$TMP_DIR/pull.timer.in" "$TMP_DIR/$NAME-pull.timer"

sudo install -m 644 "$TMP_DIR/$NAME-pull.service" "/etc/systemd/system/$NAME-pull.service"
sudo install -m 644 "$TMP_DIR/$NAME-pull.timer" "/etc/systemd/system/$NAME-pull.timer"
sudo systemctl daemon-reload
sudo systemctl enable --now "$NAME-pull.timer"

systemctl list-timers | grep "$NAME" || true
