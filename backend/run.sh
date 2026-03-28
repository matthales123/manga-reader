#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi

. .venv/bin/activate

if [[ ! -f .venv/.deps_installed ]]; then
  pip install -r requirements.txt
  touch .venv/.deps_installed
fi

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"

exec uvicorn app.main:app --host "$HOST" --port "$PORT"
