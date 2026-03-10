#!/bin/sh
#
# lima-fix-ssh.sh — One-time SSH key injection into the Lima FreeBSD VM.
#
# Root cause: Lima's cloud-config sets homedir="/home/<user>" but on FreeBSD
# /home may not exist during cloud-init, so authorized_keys is never written.
#
# Resolution: reads the exact homedir from Lima's cloud-config.yaml on the HOST
# (no VM-side variable capture), base64-encodes the setup script, and sends it
# as a single command via the QEMU serial socket.  No SSH required.
#
# Requires: expect   (brew install expect)
#
# Usage:
#   sh scripts/lima-fix-ssh.sh [instance-name]
#   make lima-fix-ssh

set -e

INST="${1:-freebsd14}"
LIMA_DIR="${HOME}/.lima/${INST}"
SERIAL_SOCK="${LIMA_DIR}/serial.sock"
PUBKEY_FILE="${HOME}/.lima/_config/user.pub"
CLOUD_CFG="${LIMA_DIR}/cloud-config.yaml"

# ── Pre-flight ────────────────────────────────────────────────────────────────
[ -S "${SERIAL_SOCK}" ] || {
    echo "ERROR: serial socket not found — is the VM running?"
    echo "       Run: make vm-start"
    exit 1
}
[ -f "${PUBKEY_FILE}" ] || { echo "ERROR: ${PUBKEY_FILE} not found"; exit 1; }
[ -f "${CLOUD_CFG}" ]   || { echo "ERROR: ${CLOUD_CFG} not found";   exit 1; }
command -v expect >/dev/null 2>&1 || {
    echo "ERROR: 'expect' is required.  Install: brew install expect"
    exit 1
}

PUBKEY=$(cat "${PUBKEY_FILE}")

# Read homedir directly from Lima's cloud-config.yaml on the host.
# Avoids VM-side variable capture which ANSI escape codes corrupt.
UHOME=$(grep 'homedir:' "${CLOUD_CFG}" | head -1 \
    | sed 's/.*homedir: *//;s/"//g;s/[[:space:]]*$//')
SSH_USER=$(grep '  - name:' "${CLOUD_CFG}" | head -1 \
    | sed 's/.*- name: *//;s/"//g;s/[[:space:]]*$//')
[ -n "${UHOME}" ]    || UHOME="/home/freebsd.guest"
[ -n "${SSH_USER}" ] || SSH_USER="freebsd"

echo "==> Lima instance : ${INST}"
echo "==> SSH user      : ${SSH_USER}"
echo "==> Home dir      : ${UHOME}"
echo ""
echo "==> Injecting SSH key via serial console (takes ~15 s)..."

# ── Build the setup script with all paths pre-expanded on the host. ──────────
# Base64-encode it so it can be sent as a single terminal line — no newlines,
# no ANSI escape issues.
SETUP=$(printf '%s\n' \
    '#!/bin/sh' \
    'set -e' \
    "mkdir -p '${UHOME}/.ssh'" \
    "printf '%s\n' '${PUBKEY}' > '${UHOME}/.ssh/authorized_keys'" \
    "chmod 700 '${UHOME}/.ssh'" \
    "chmod 600 '${UHOME}/.ssh/authorized_keys'" \
    "chown -R '${SSH_USER}' '${UHOME}/.ssh'" \
    'service sshd reload >/dev/null 2>&1' \
    'echo LIMA_KEY_OK')

B64=$(printf '%s' "${SETUP}" | base64 | tr -d '\n')

# ── Write the expect script via Python (cleanest way to embed / and ! in strings)
EXP=$(mktemp /tmp/lima-fix-XXXXXX.exp)
trap 'rm -f "${EXP}"' EXIT

python3 - "${EXP}" "${SERIAL_SOCK}" "${B64}" "${UHOME}" << 'PYEOF'
import sys
path, sock, b64, uhome = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
script = """set timeout 60
spawn nc -U {sock}

send "\\r"
after 2000
send "\\r"

expect {{
    \"login:"    {{ send \"root\\r\"; exp_continue }}
    \"Password:" {{ send \"\\r\";    exp_continue }}
    \"#\"         {{}}
    timeout     {{ puts \"ERROR: no shell prompt\"; exit 1 }}
}}

send \"echo {b64} | base64 -d | sh\\r\"

expect {{
    \"LIMA_KEY_OK\" {{ puts \"\\n==> Key written to {uhome}/.ssh/authorized_keys\" }}
    timeout       {{ puts \"ERROR: injection timed out\"; exit 1 }}
}}
expect \"#\"
""".format(sock=sock, b64=b64, uhome=uhome)
open(path, 'w').write(script)
PYEOF

expect "${EXP}"
RC=$?
[ ${RC} -eq 0 ] || { echo "ERROR: expect script failed (exit ${RC})"; exit ${RC}; }

echo ""
echo "==> Testing SSH access..."
sleep 2
if limactl shell "${INST}" -- uname -sr 2>/dev/null; then
    echo "==> SUCCESS: Lima SSH is working for ${INST}"
    echo "    You can now run:  make build-vm"
else
    echo "WARNING: SSH still failing.  Serial log: ${LIMA_DIR}/serial.log"
fi
