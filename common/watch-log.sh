#!/usr/bin/env bash
# Follow the log of the latest run
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
tail -f "$(ls -t "$SCRIPT_DIR"/log/*.log | head -1)"
