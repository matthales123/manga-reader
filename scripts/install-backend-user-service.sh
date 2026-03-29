#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-manga-reader-backend.service}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${BACKEND_DIR:-${REPO_ROOT}/backend}"
UNIT_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"
UNIT_PATH="${UNIT_DIR}/${SERVICE_NAME}"

if [[ ! -x "${BACKEND_DIR}/run.sh" ]]; then
  echo "Expected executable backend runner at: ${BACKEND_DIR}/run.sh"
  exit 1
fi

mkdir -p "${UNIT_DIR}"

cat > "${UNIT_PATH}" <<EOF
[Unit]
Description=Manga Reader Backend (FastAPI)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${BACKEND_DIR}
ExecStart=${BACKEND_DIR}/run.sh
Restart=always
RestartSec=3
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
EOF

echo "Wrote unit: ${UNIT_PATH}"

systemctl --user daemon-reload
systemctl --user enable --now "${SERVICE_NAME}"

echo
echo "Service started. Check status with:"
echo "  systemctl --user status ${SERVICE_NAME}"
echo
echo "View logs with:"
echo "  journalctl --user -u ${SERVICE_NAME} -f"
echo
echo "Optional (requires sudo): keep user services running after logout/reboot:"
echo "  sudo loginctl enable-linger ${USER}"
