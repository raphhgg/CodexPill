#!/usr/bin/env bash
set -euo pipefail

pkill -x "rusage" >/dev/null 2>&1 || true
