#!/usr/bin/env bash
# Installs the script and systemd units for one provider (gdrive, icloud, ...)
# using the provider's provider.conf and the shared config.yml in the repository root.
# Not run directly: <provider>/deploy.sh calls it with the provider directory.
# Run as run_user (sudo is invoked internally).
set -euo pipefail

COMMON="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
HERE="$(cd "${1:?Usage: deploy.sh <provider dir>}" && pwd)"

# shellcheck source=config.sh
. "$COMMON/config.sh"
cfg_load "$COMMON/../config.yml"

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

RUN_USER="$(cfg run_user)"
MOUNT_POINT="$(cfg mount_point)"
APP_DIR="$(cfg app_dir)"
# systemd OnCalendar expression; optional, every 15 minutes by default
SCHEDULE="$(cfg schedule)"
SCHEDULE="${SCHEDULE:-*:0/15}"
# Optional pull.sh limits; when unset, the defaults in pull.sh apply
MIN_FREE_GB="$(cfg min_free_gb)"
KEEP_LOG_DAYS="$(cfg keep_log_days)"
SRC_REMOTE="$(cfg_get "providers.$NAME.src_remote")"
DST_DIR="$(cfg_get "providers.$NAME.dst_dir")"

# variable:key it is read from (for the error message)
for pair in "RUN_USER:common.run_user" "APP_DIR:common.app_dir" \
            "SRC_REMOTE:providers.$NAME.src_remote" "DST_DIR:providers.$NAME.dst_dir"; do
  var="${pair%%:*}"
  if [ -z "${!var}" ]; then
    echo "${pair#*:} is not set in config.yml" >&2
    exit 1
  fi
done

for pair in "min_free_gb:$MIN_FREE_GB" "keep_log_days:$KEEP_LOG_DAYS"; do
  if [ -n "${pair#*:}" ] && [[ ! "${pair#*:}" =~ ^[0-9]+$ ]]; then
    echo "${pair%%:*} must be a whole number, got '${pair#*:}'" >&2
    exit 1
  fi
done

if command -v systemd-analyze >/dev/null 2>&1 && ! systemd-analyze calendar "$SCHEDULE" >/dev/null 2>&1; then
  echo "schedule '$SCHEDULE' is not a valid systemd calendar expression (see: systemd-analyze calendar)" >&2
  exit 1
fi

if [ "$(id -un)" != "$RUN_USER" ]; then
  echo "Run as user $RUN_USER (not via sudo)" >&2
  exit 1
fi

# mount_point is optional: set it only when the data lives on a separate mounted disk
if [ -n "$MOUNT_POINT" ]; then
  case "$DST_DIR/" in
    "${MOUNT_POINT%/}"/*) ;;
    *) echo "providers.$NAME.dst_dir ($DST_DIR) must be inside mount_point ($MOUNT_POINT)" >&2; exit 1 ;;
  esac
fi

# nested <dir> <parent>: true if dir is parent itself or lies inside it
nested() { case "${1%/}/" in "${2%/}/"*) return 0 ;; *) return 1 ;; esac; }

# Two providers must not copy into the same directory (or one inside the other):
# their locks are separate, so the syncs would run concurrently on the same files
for other_conf in "$COMMON"/../*/provider.conf; do
  [ -f "$other_conf" ] || continue
  other_dir="$(cd "$(dirname "$other_conf")" && pwd)"
  [ "$other_dir" = "$HERE" ] && continue
  other_name="$(provider_name "$other_dir")"
  [ -n "$other_name" ] || continue
  other_dst="$(cfg_get "providers.$other_name.dst_dir")"
  [ -n "$other_dst" ] || continue
  if nested "$DST_DIR" "$other_dst" || nested "$other_dst" "$DST_DIR"; then
    echo "providers.$NAME.dst_dir ($DST_DIR) overlaps providers.$other_name.dst_dir ($other_dst): use separate directories" >&2
    exit 1
  fi
done

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

# Same lock as pull.sh: do not replace files under a running sync
# and do not let two deploys of one provider run at once
exec 8>"$INSTALL_DIR/.lock"
if ! flock -n 8; then
  echo "$NAME-pull is running (or another deploy is in progress); rerun deploy.sh later" >&2
  exit 1
fi

strip_cr "$COMMON/pull.sh" "$TMP_DIR/pull.sh"
strip_cr "$COMMON/watch-log.sh" "$TMP_DIR/watch-log.sh"
strip_cr "$COMMON/pull.timer.in" "$TMP_DIR/pull.timer.in"
strip_cr "$COMMON/pull.service.in" "$TMP_DIR/pull.service.in"

# The installed .env holds only this provider's resolved settings
printf 'SRC_REMOTE=%q\nDST_DIR=%q\nMOUNT_POINT=%q\n' "$SRC_REMOTE" "$DST_DIR" "$MOUNT_POINT" > "$TMP_DIR/app.env"
[ -z "$MIN_FREE_GB" ] || printf 'MIN_FREE_GB=%q\n' "$MIN_FREE_GB" >> "$TMP_DIR/app.env"
[ -z "$KEEP_LOG_DAYS" ] || printf 'KEEP_LOG_DAYS=%q\n' "$KEEP_LOG_DAYS" >> "$TMP_DIR/app.env"

install -m 755 "$TMP_DIR/pull.sh" "$INSTALL_DIR/$NAME-pull.sh"
install -m 755 "$TMP_DIR/watch-log.sh" "$INSTALL_DIR/watch-log.sh"
install -m 644 "$TMP_DIR/provider.conf" "$INSTALL_DIR/provider.conf"
install -m 600 "$TMP_DIR/app.env" "$INSTALL_DIR/.env"

render() {
  sed -e "s|@NAME@|$NAME|g" \
      -e "s|@DESCRIPTION@|$DESCRIPTION|g" \
      -e "s|@RUN_USER@|$RUN_USER|g" \
      -e "s|@INSTALL_DIR@|$INSTALL_DIR|g" \
      -e "s|@DST_DIR@|$DST_DIR|g" \
      -e "s|@SCHEDULE@|$SCHEDULE|g" \
      "$1" > "$2"
}
render "$TMP_DIR/pull.service.in" "$TMP_DIR/$NAME-pull.service"
render "$TMP_DIR/pull.timer.in" "$TMP_DIR/$NAME-pull.timer"

sudo install -m 644 "$TMP_DIR/$NAME-pull.service" "/etc/systemd/system/$NAME-pull.service"
sudo install -m 644 "$TMP_DIR/$NAME-pull.timer" "/etc/systemd/system/$NAME-pull.timer"
sudo systemctl daemon-reload
sudo systemctl enable "$NAME-pull.timer"
# restart, not just --now: an already active timer would keep the old schedule
sudo systemctl restart "$NAME-pull.timer"

systemctl list-timers | grep "$NAME" || true
