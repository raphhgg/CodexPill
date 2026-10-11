#!/usr/bin/env bash
set -euo pipefail

pkill -x "Refill" >/dev/null 2>&1 || true
