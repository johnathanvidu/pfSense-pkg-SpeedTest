#!/bin/sh
#
# deploy.sh — Push pfSense-pkg-speedtest files to a pfSense box over SSH.
#
# Fastest workflow for development: no .pkg build, no VM required.
# Files are copied directly and registered in pfSense config via PHP.
#
# Usage (via Makefile):   make deploy HOST=192.168.1.1
# Usage (direct):         sh scripts/deploy.sh <host> [user]
#
# SSH authentication:
#   Preferred:  SSH key already added to pfSense authorized_keys
#   Fallback:   Set SSH_PASS in .env (requires: brew install sshpass)
#

set -e

# Load .env when invoked directly (make deploy already exports the vars)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${REPO_ROOT}/.env"
    set +a
fi

# Map SSH_PASS -> SSHPASS for the sshpass tool
: "${SSHPASS:=${SSH_PASS:-}}"
export SSHPASS

HOST="${1:?Usage: $0 <pfsense-host> [user]}"
USER="${2:-${SSH_USER:-admin}}"
TARGET="${USER}@${HOST}"

# Resolve SSH/SCP wrappers (key auth preferred, sshpass when SSH_PASS is set)
if [ -n "${SSHPASS}" ]; then
    SSH="sshpass -e ssh"
    SCP="sshpass -e scp"
else
    SSH="ssh"
    SCP="scp"
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=no"

FILES="pfSense-pkg-speedtest/files"

echo "==> Deploying to ${TARGET} ..."

# Create all required directories on pfSense
${SSH} ${SSH_OPTS} "${TARGET}" \
    "mkdir -p \
        /usr/local/pkg \
        /usr/local/www/speedtest \
        /usr/local/www/widgets/widgets \
        /usr/local/bin \
        /etc/inc/priv \
        /var/db/speedtest"

# Copy package files (group transfers by destination directory)
${SCP} ${SSH_OPTS} \
    "${FILES}/usr/local/pkg/speedtest.xml" \
    "${FILES}/usr/local/pkg/speedtest.inc" \
    "${TARGET}:/usr/local/pkg/"

${SCP} ${SSH_OPTS} \
    "${FILES}/usr/local/www/speedtest/speedtest.php" \
    "${TARGET}:/usr/local/www/speedtest/"

${SCP} ${SSH_OPTS} \
    "${FILES}/usr/local/www/widgets/widgets/speedtest.widget.php" \
    "${TARGET}:/usr/local/www/widgets/widgets/"

${SCP} ${SSH_OPTS} \
    "${FILES}/usr/local/bin/speedtest_runner.sh" \
    "${TARGET}:/usr/local/bin/"

# Priv file goes directly to its runtime location (no staging needed for deploys)
${SCP} ${SSH_OPTS} \
    "${FILES}/etc/inc/priv/speedtest.priv.inc" \
    "${TARGET}:/etc/inc/priv/"

# Fix permissions
${SSH} ${SSH_OPTS} "${TARGET}" \
    "chmod 755 /usr/local/bin/speedtest_runner.sh && \
     chmod 644 \
         /usr/local/pkg/speedtest.xml \
         /usr/local/pkg/speedtest.inc \
         /usr/local/www/speedtest/speedtest.php \
         /usr/local/www/widgets/widgets/speedtest.widget.php \
         /etc/inc/priv/speedtest.priv.inc"

# Register package with pfSense (adds Services menu entry, records in config.xml)
${SSH} ${SSH_OPTS} "${TARGET}" \
    "php -r \"
        require_once('/etc/inc/config.inc');
        require_once('/etc/inc/util.inc');
        require_once('/usr/local/pkg/speedtest.inc');
        speedtest_install();
        echo 'Registration: OK' . PHP_EOL;
    \""

echo ""
echo "==> Done. Navigate to: https://${HOST}/speedtest/speedtest.php"
echo "    (Services > Speed Test menu entry appears on next page load)"
