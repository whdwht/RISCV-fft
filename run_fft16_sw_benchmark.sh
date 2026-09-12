#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python_bin="${PYTHON_BIN:-}"
if [[ -z "${python_bin}" ]]; then
  if command -v python >/dev/null 2>&1; then
    python_bin="python"
  elif command -v python3 >/dev/null 2>&1; then
    python_bin="python3"
  else
    echo "ERROR: Python 2.7 or Python 3 is required" >&2
    exit 2
  fi
fi
exec "${python_bin}" "${script_dir}/sim_16/fft16_benchmark.py" "$@"
