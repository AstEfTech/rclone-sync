#!/usr/bin/env bash
# Minimal reader for config.yml plus provider helpers, sourced by the deploy/undeploy
# scripts (no yq/python needed).
# Supported subset of YAML: nested mappings indented with 2 spaces, "key: value"
# scalars (optionally in single or double quotes), full-line and trailing "# comments".
# Lists, anchors and multi-line values are not supported.

# cfg_load <file>: flattens the file once into lines "a.b.c=value"; exits if the file is missing
cfg_load() {
  if [ ! -f "$1" ]; then
    echo "Missing $1: cp config.example.yml config.yml and fill it in" >&2
    exit 1
  fi
  CFG="$(sed 's/\r$//' "$1" | awk '
    /^[[:space:]]*(#|$)/ { next }
    {
      match($0, /^ */)
      depth = int(RLENGTH / 2)
      line = substr($0, RLENGTH + 1)
      i = index(line, ":")
      if (!i) next
      path[depth] = substr(line, 1, i - 1)
      val = substr(line, i + 1)
      sub(/^[[:space:]]+/, "", val)
      if (val == "" || val ~ /^#/) next
      if (val ~ /^"/)         { sub(/^"/, "", val);    sub(/".*$/, "", val) }
      else if (val ~ "^\047") { sub(/^\047/, "", val); sub(/\047.*$/, "", val) }
      else                    { sub(/[[:space:]]+#.*$/, "", val); sub(/[[:space:]]+$/, "", val) }
      key = path[0]
      for (d = 1; d <= depth; d++) key = key "." path[d]
      print key "=" val
    }')"
}

# cfg_get <a.b.c>: value from the loaded config (empty if absent)
cfg_get() {
  sed -n "s/^${1//./\\.}=//p" <<<"$CFG" | head -n 1
}

# cfg_children <a.b>: names of the direct child mappings of a.b, in file order (one per line)
cfg_children() {
  sed -n "s/^${1//./\\.}\.\([^.=]*\)\..*/\1/p" <<<"$CFG" | awk '!seen[$0]++'
}

# cfg <key>: providers.$NAME.<key>, else common.<key> (the provider block overrides common)
cfg() {
  local v
  v="$(cfg_get "providers.$NAME.$1")"
  [ -n "$v" ] || v="$(cfg_get "common.$1")"
  printf '%s' "$v"
}

# provider_name <provider dir>: NAME from the provider's provider.conf (empty if unset)
provider_name() {
  sed 's/\r$//' "$1/provider.conf" | ( . /dev/stdin; echo "${NAME:-}" )
}
