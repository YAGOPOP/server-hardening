#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK_FILE="${PROJECT_DIR}/playbook.yml"

TMP_DIR="$(mktemp -d)"
INVENTORY_FILE="${TMP_DIR}/inventory.ini"
VARS_FILE="${TMP_DIR}/vars.yml"

cleanup() {
  rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

echo "=== Basic server hardening with Ansible ==="
echo

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "Error: ansible-playbook is not installed."
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: openssl is not installed."
  exit 1
fi

if [[ ! -f "${PLAYBOOK_FILE}" ]]; then
  echo "Error: playbook.yml not found in ${PROJECT_DIR}"
  exit 1
fi

read -rp "Server IP: " SERVER_IP

if [[ -z "${SERVER_IP}" ]]; then
  echo "Error: server IP is required."
  exit 1
fi

read -rp "New sudo username [deploy]: " NEW_USER
NEW_USER="${NEW_USER:-deploy}"

read -rp "SSH port [22]: " SSH_PORT
SSH_PORT="${SSH_PORT:-22}"

read -rp "Path to public SSH key [${HOME}/.ssh/id_ed25519.pub]: " PUBLIC_KEY_PATH
PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-${HOME}/.ssh/id_ed25519.pub}"

PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH/#\~/${HOME}}"

if [[ ! -f "${PUBLIC_KEY_PATH}" ]]; then
  echo "Error: public key not found: ${PUBLIC_KEY_PATH}"
  exit 1
fi

echo
echo "Enter password for new sudo user: ${NEW_USER}"
read -rsp "Password: " USER_PASSWORD
echo
read -rsp "Repeat password: " USER_PASSWORD_CONFIRM
echo

if [[ "${USER_PASSWORD}" != "${USER_PASSWORD_CONFIRM}" ]]; then
  echo "Error: passwords do not match."
  exit 1
fi

if [[ -z "${USER_PASSWORD}" ]]; then
  echo "Error: password cannot be empty."
  exit 1
fi

USER_PASSWORD_HASH="$(printf '%s\n' "${USER_PASSWORD}" | openssl passwd -6 -stdin)"

unset USER_PASSWORD
unset USER_PASSWORD_CONFIRM

cat > "${INVENTORY_FILE}" <<EOF
[servers]
target ansible_host=${SERVER_IP} ansible_user=root ansible_port=${SSH_PORT} ansible_python_interpreter=/usr/bin/python3
EOF

cat > "${VARS_FILE}" <<EOF
---
new_user: "${NEW_USER}"
new_user_password_hash: '${USER_PASSWORD_HASH}'
ssh_port: ${SSH_PORT}
public_key_path: "${PUBLIC_KEY_PATH}"
EOF

chmod 600 "${INVENTORY_FILE}" "${VARS_FILE}"

echo
echo "Inventory and vars files were created temporarily."
echo "Root password will be requested by Ansible via --ask-pass."
echo

ansible-playbook \
  -i "${INVENTORY_FILE}" \
  "${PLAYBOOK_FILE}" \
  --extra-vars "@${VARS_FILE}" \
  --ask-pass \
  --ssh-common-args="-o StrictHostKeyChecking=accept-new"

echo
echo "Done."
echo
echo "Now test login in a NEW terminal before closing your current root session:"
echo
echo "  ssh -p ${SSH_PORT} ${NEW_USER}@${SERVER_IP}"
echo
echo "Then test sudo:"
echo
echo "  sudo whoami"
