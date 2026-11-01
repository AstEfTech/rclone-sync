#!/usr/bin/env bash
# Deploys (or redeploys) every provider that has a block under `providers` in config.yml:
# run it after editing config.yml to apply the changes everywhere.
# Providers without a block are skipped; a failure in one does not stop the others.
# Run as run_user (sudo is invoked internally); one provider: <provider>/deploy.sh.
set -uo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# shellcheck source=common/config.sh
. "$ROOT/common/config.sh"
cfg_load "$ROOT/config.yml"

deployed=() skipped=() failed=()
for conf in "$ROOT"/*/provider.conf; do
  [ -f "$conf" ] || continue
  dir="$(dirname "$conf")"
  name="$(provider_name "$dir")"
  if [ -z "$name" ] || [ -z "$(cfg_get "providers.$name.dst_dir")" ]; then
    skipped+=("$(basename "$dir")")
    continue
  fi
  echo "=== $name"
  if bash "$ROOT/common/deploy.sh" "$dir"; then
    deployed+=("$name")
  else
    failed+=("$name")
  fi
done

echo
echo "Deployed: ${deployed[*]:-none}"
[ "${#skipped[@]}" -eq 0 ] || echo "Skipped (no block in config.yml): ${skipped[*]}"
[ "${#failed[@]}" -eq 0 ] || { echo "FAILED: ${failed[*]}" >&2; exit 1; }
