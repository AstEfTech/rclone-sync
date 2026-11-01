#!/usr/bin/env bash
# Installs the script and systemd units for providers (gdrive, icloud, ...) using each
# provider's provider.conf and the shared config.yml in the repository root.
# Usage: ./deploy.sh [provider|all]
#   provider  deploy just that one
#   all       every provider that has a block under `providers` in config.yml
#             (providers without a block are skipped; a failure in one does not stop the others)
#   (none)    choose from the list on a terminal; without a terminal the same as `all`
# Run it again after editing config.yml to apply the changes. Run as run_user
# (sudo is invoked internally).
set -uo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
COMMON="$ROOT/common"

# shellcheck source=common/config.sh
. "$COMMON/config.sh"
cfg_load "$ROOT/config.yml"

# deploy_one <provider dir>: installs one provider. A subshell, so `exit` only ends this
# provider; call it as a plain statement (not in `if`/`||`), or set -e is ignored inside.
deploy_one() (
set -euo pipefail
HERE="$1"

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

# variable:key it is read from (for the error message)
for pair in "RUN_USER:common.run_user" "APP_DIR:common.app_dir"; do
  var="${pair%%:*}"
  if [ -z "${!var}" ]; then
    echo "${pair#*:} is not set in config.yml" >&2
    exit 1
  fi
done

# Folder pairs: providers.<NAME>.pairs.<pair>.{src,dst,mode}; mode falls back to the
# provider block, then common, then copy
PAIR_NAMES=() PAIR_SRC=() PAIR_DST=() PAIR_MODE=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  key="providers.$NAME.pairs.$p"
  src="$(cfg_get "$key.src")"
  dst="$(cfg_get "$key.dst")"
  mode="$(cfg_get "$key.mode")"
  [ -n "$mode" ] || mode="$(cfg mode)"
  mode="${mode:-copy}"
  for pair in "src:$src" "dst:$dst"; do
    if [ -z "${pair#*:}" ]; then
      echo "$key.${pair%%:*} is not set in config.yml" >&2
      exit 1
    fi
  done
  if [[ ! "$p" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "pair name '$p' under providers.$NAME.pairs: use only letters, digits, - and _" >&2
    exit 1
  fi
  case "$mode" in
    copy|sync|move|copyto|moveto|bisync|twoway) ;;
    *) echo "$key.mode must be copy, sync, move, copyto, moveto, bisync or twoway, got '$mode'" >&2; exit 1 ;;
  esac
  if [[ "$src" != *:* ]]; then
    echo "$key.src ($src) must be <remote>:<path>" >&2
    exit 1
  fi
  PAIR_NAMES+=("$p") PAIR_SRC+=("$src") PAIR_DST+=("$dst") PAIR_MODE+=("$mode")
done < <(cfg_children "providers.$NAME.pairs")
if [ "${#PAIR_NAMES[@]}" -eq 0 ]; then
  echo "providers.$NAME.pairs has no folder pairs in config.yml" >&2
  exit 1
fi

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
  for i in "${!PAIR_NAMES[@]}"; do
    case "${PAIR_DST[$i]}/" in
      "${MOUNT_POINT%/}"/*) ;;
      *) echo "providers.$NAME.pairs.${PAIR_NAMES[$i]}.dst (${PAIR_DST[$i]}) must be inside mount_point ($MOUNT_POINT)" >&2; exit 1 ;;
    esac
  done
fi

# nested <dir> <parent>: true if dir is parent itself or lies inside it
nested() { case "${1%/}/" in "${2%/}/"*) return 0 ;; *) return 1 ;; esac; }

# No two pairs (of this or another provider) may use the same destination directory or
# nest one inside the other: provider locks are separate, so syncs would run concurrently
# on the same files, and a sync pair would delete what another pair put there
labels=() dsts=()
for i in "${!PAIR_NAMES[@]}"; do
  labels+=("providers.$NAME.pairs.${PAIR_NAMES[$i]}") dsts+=("${PAIR_DST[$i]}")
done
own=${#labels[@]}
for other_conf in "$ROOT"/*/provider.conf; do
  [ -f "$other_conf" ] || continue
  other_dir="$(cd "$(dirname "$other_conf")" && pwd)"
  [ "$other_dir" = "$HERE" ] && continue
  other_name="$(provider_name "$other_dir")"
  [ -n "$other_name" ] || continue
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    d="$(cfg_get "providers.$other_name.pairs.$p.dst")"
    [ -n "$d" ] || continue
    labels+=("providers.$other_name.pairs.$p") dsts+=("$d")
  done < <(cfg_children "providers.$other_name.pairs")
done
for ((a = 0; a < own; a++)); do
  for ((b = 0; b < ${#labels[@]}; b++)); do
    [ "$a" -eq "$b" ] && continue
    [ "$b" -lt "$own" ] && [ "$b" -lt "$a" ] && continue
    if nested "${dsts[$a]}" "${dsts[$b]}" || nested "${dsts[$b]}" "${dsts[$a]}"; then
      echo "${labels[$a]}.dst (${dsts[$a]}) overlaps ${labels[$b]}.dst (${dsts[$b]}): use separate directories" >&2
      exit 1
    fi
  done
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

REMOTES="$(rclone listremotes)"
for src in "${PAIR_SRC[@]}"; do
  REMOTE_NAME="${src%%:*}:"
  if ! grep -qxF "$REMOTE_NAME" <<<"$REMOTES"; then
    echo "rclone remote '$REMOTE_NAME' not found for user $RUN_USER." >&2
    echo "Configure it first: see $PROVIDER/CONNECTION_README.md" >&2
    exit 1
  fi
done

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
{
  printf 'MOUNT_POINT=%q\n' "$MOUNT_POINT"
  for arr in PAIR_NAMES PAIR_SRC PAIR_DST PAIR_MODE; do
    declare -n ref="$arr"
    printf '%s=(' "$arr"; printf ' %q' "${ref[@]}"; printf ' )\n'
  done
} > "$TMP_DIR/app.env"
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
      -e "s|@DST_DIRS@|${PAIR_DST[*]}|g" \
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
)

names=() dirs=()
for conf in "$ROOT"/*/provider.conf; do
  [ -f "$conf" ] || continue
  dir="$(dirname "$conf")"
  name="$(provider_name "$dir")"
  [ -n "$name" ] || continue
  names+=("$name")
  dirs+=("$dir")
done

if [ "${#names[@]}" -eq 0 ]; then
  echo "No providers found (no */provider.conf with NAME set)" >&2
  exit 1
fi

choice="${1:-}"
if [ -z "$choice" ]; then
  if [ -t 0 ]; then
    echo "Providers:"
    for i in "${!names[@]}"; do echo "  $((i + 1))) ${names[$i]}"; done
    echo "  a) all (every provider that has a block in config.yml)"
    read -r -p "Deploy which one? [1-${#names[@]}, name or a, empty = cancel] " choice
    [ -n "$choice" ] || { echo "Aborted"; exit 1; }
  else
    choice=all
  fi
fi
[ "$choice" = a ] && choice=all

targets=()
if [ "$choice" = all ]; then
  for i in "${!names[@]}"; do targets+=("$i"); done
else
  for i in "${!names[@]}"; do
    if [ "$choice" = "${names[$i]}" ] || [ "$choice" = "$((i + 1))" ]; then
      targets+=("$i")
    fi
  done
  if [ "${#targets[@]}" -eq 0 ]; then
    echo "Unknown provider: $choice (available: ${names[*]})" >&2
    exit 1
  fi
fi

deployed=() skipped=() failed=()
for i in "${targets[@]}"; do
  name="${names[$i]}"
  if [ "$choice" = all ] && [ -z "$(cfg_children "providers.$name.pairs")" ]; then
    skipped+=("$name")
    continue
  fi
  echo "=== $name"
  rc=0
  deploy_one "${dirs[$i]}" || rc=$?
  if [ "$rc" -eq 0 ]; then deployed+=("$name"); else failed+=("$name"); fi
done

echo
echo "Deployed: ${deployed[*]:-none}"
[ "${#skipped[@]}" -eq 0 ] || echo "Skipped (no block in config.yml): ${skipped[*]}"
[ "${#failed[@]}" -eq 0 ] || { echo "FAILED: ${failed[*]}" >&2; exit 1; }
