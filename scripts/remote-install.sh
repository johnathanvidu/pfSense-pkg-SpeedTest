#!/bin/sh
#
# remote-install.sh — Build and install pfSense-pkg-speedtest on the pfSense
#                     box using its own native pkg create.
#
# Avoids macOS/FreeBSD pkg-format incompatibilities by never creating a .pkg
# on macOS.  Instead:
#   1. Upload source files to /tmp/pkg-stage-<pid>/ on pfSense
#   2. SSH: run pkg create → /tmp/pfSense-pkg-speedtest-<ver>.pkg
#   3. SSH: pkg delete old, pkg add new
#   4. SSH: php speedtest_install() to register with pfSense
#
# Usage (via Makefile):  make install HOST=<ip>
# Usage (direct):        sh scripts/remote-install.sh <host> [user] [version]
#

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
    set -a; . "${REPO_ROOT}/.env"; set +a
fi

: "${SSHPASS:=${SSH_PASS:-}}"
export SSHPASS

HOST="${1:?Usage: $0 <pfsense-host> [user] [version]}"
RUSER="${2:-${SSH_USER:-admin}}"
VERSION="${3:-${VERSION:-1.0.0}}"
TARGET="${RUSER}@${HOST}"
PORTNAME="pfSense-pkg-speedtest"
PKGNAME="${PORTNAME}-${VERSION}"
FILES="${REPO_ROOT}/pfSense-pkg-speedtest/files"

if [ -n "${SSHPASS}" ]; then
    SSH="sshpass -e ssh"; SCP="sshpass -e scp"
else
    SSH="ssh"; SCP="scp"
fi
SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=no"

# Use local PID for a unique remote workspace that we can clean up reliably
REMOTE_WORK="/tmp/pkg-work-$$"

# ---------------------------------------------------------------------------
# 1. Upload source files (flat layout to simplify SCP)
# ---------------------------------------------------------------------------
echo "==> Uploading source files to ${HOST}..."

LOCAL_FLAT="$(mktemp -d)"
mkdir -p "${LOCAL_FLAT}/bin" "${LOCAL_FLAT}/pkg" "${LOCAL_FLAT}/www" "${LOCAL_FLAT}/priv"
cp "${FILES}/usr/local/bin/speedtest_runner.sh"                  "${LOCAL_FLAT}/bin/"
cp "${FILES}/usr/local/pkg/speedtest.inc"                        "${LOCAL_FLAT}/pkg/"
cp "${FILES}/usr/local/pkg/speedtest.xml"                        "${LOCAL_FLAT}/pkg/"
cp "${FILES}/usr/local/www/speedtest/speedtest.php"              "${LOCAL_FLAT}/www/"
cp "${FILES}/usr/local/www/widgets/widgets/speedtest.widget.php" "${LOCAL_FLAT}/www/"
cp "${FILES}/etc/inc/priv/speedtest.priv.inc"                    "${LOCAL_FLAT}/priv/"

${SSH} ${SSH_OPTS} "${TARGET}" "rm -rf '${REMOTE_WORK}' && mkdir -p '${REMOTE_WORK}/src'"
${SCP} ${SSH_OPTS} -r \
    "${LOCAL_FLAT}/bin" "${LOCAL_FLAT}/pkg" "${LOCAL_FLAT}/www" "${LOCAL_FLAT}/priv" \
    "${TARGET}:${REMOTE_WORK}/src/"
rm -rf "${LOCAL_FLAT}"

# ---------------------------------------------------------------------------
# 2. Write the build script locally (no quoting gymnastics on the remote side)
# ---------------------------------------------------------------------------
BUILD_SH="$(mktemp)"
# All shell variables below are expanded NOW by the LOCAL shell (that is the
# intent — values are baked into the script that runs on pfSense).
cat > "${BUILD_SH}" << ENDBUILD
#!/bin/sh
set -e

PORTNAME="${PORTNAME}"
VERSION="${VERSION}"
PKGNAME="${PKGNAME}"
SRC="${REMOTE_WORK}/src"
STAGE="${REMOTE_WORK}/stage"
BUILD="${REMOTE_WORK}/build"

mkdir -p \\
    "\${STAGE}/usr/local/bin" \\
    "\${STAGE}/usr/local/pkg" \\
    "\${STAGE}/usr/local/www/speedtest" \\
    "\${STAGE}/usr/local/www/widgets/widgets" \\
    "\${STAGE}/usr/local/share/\${PORTNAME}" \\
    "\${BUILD}"

cp "\${SRC}/bin/speedtest_runner.sh"    "\${STAGE}/usr/local/bin/"
cp "\${SRC}/pkg/speedtest.inc"          "\${STAGE}/usr/local/pkg/"
cp "\${SRC}/pkg/speedtest.xml"          "\${STAGE}/usr/local/pkg/"
cp "\${SRC}/www/speedtest.php"          "\${STAGE}/usr/local/www/speedtest/"
cp "\${SRC}/www/speedtest.widget.php"   "\${STAGE}/usr/local/www/widgets/widgets/"
cp "\${SRC}/priv/speedtest.priv.inc"    "\${STAGE}/usr/local/share/\${PORTNAME}/"

chmod 755 "\${STAGE}/usr/local/bin/speedtest_runner.sh"
chmod 644 \\
    "\${STAGE}/usr/local/pkg/speedtest.inc" \\
    "\${STAGE}/usr/local/pkg/speedtest.xml" \\
    "\${STAGE}/usr/local/www/speedtest/speedtest.php" \\
    "\${STAGE}/usr/local/www/widgets/widgets/speedtest.widget.php" \\
    "\${STAGE}/usr/local/share/\${PORTNAME}/speedtest.priv.inc"

# UCL manifest (pkg create fills in file hashes from the plist + stage)
printf '%s\n' \\
    'name = "'"${PORTNAME}"'"' \\
    'version = "'"${VERSION}"'"' \\
    'origin = "sysutils/'"${PORTNAME}"'"' \\
    'comment = "pfSense package for Ookla Speedtest CLI"' \\
    'desc = "Integrates the Ookla Speedtest CLI into the pfSense web GUI."' \\
    'maintainer = "johnathan.vidu@gmail.com"' \\
    'www = "https://github.com/johnathanvidu/pfSense-pkg-SpeedTest"' \\
    'prefix = "/usr/local"' \\
    'abi = "FreeBSD:*:*"' \\
    'arch = "freebsd:*:*"' \\
    'scripts = {' \\
    '  post-install = "/bin/sh -c \\"set -e; mkdir -p /etc/inc/priv; cp /usr/local/share/'"${PORTNAME}"'/speedtest.priv.inc /etc/inc/priv/speedtest.priv.inc; chmod 644 /etc/inc/priv/speedtest.priv.inc; mkdir -p /var/db/speedtest\\";' \\
    '  pre-deinstall = "/bin/sh -c \\"rm -f /etc/inc/priv/speedtest.priv.inc\\";' \\
    '}' \\
    > "\${BUILD}/manifest.ucl"

# Plist: paths relative to PREFIX (/usr/local)
printf '%s\n' \\
    'bin/speedtest_runner.sh' \\
    'pkg/speedtest.inc' \\
    'pkg/speedtest.xml' \\
    'www/speedtest/speedtest.php' \\
    'www/widgets/widgets/speedtest.widget.php' \\
    'share/'"${PORTNAME}"'/speedtest.priv.inc' \\
    > "\${BUILD}/plist"

echo "==> Running pkg create..."
pkg create \\
    -M "\${BUILD}/manifest.ucl" \\
    -p "\${BUILD}/plist" \\
    -r "\${STAGE}" \\
    -o /tmp

echo "==> Built: /tmp/\${PKGNAME}.pkg"
ls -lh "/tmp/\${PKGNAME}.pkg"

rm -rf "${REMOTE_WORK}"
ENDBUILD

# ---------------------------------------------------------------------------
# 3. Upload and run the build script
# ---------------------------------------------------------------------------
${SCP} ${SSH_OPTS} "${BUILD_SH}" "${TARGET}:${REMOTE_WORK}/build.sh"
rm -f "${BUILD_SH}"

echo "==> Building ${PKGNAME}.pkg on ${HOST} using native pkg create..."
${SSH} ${SSH_OPTS} "${TARGET}" "sh '${REMOTE_WORK}/build.sh'"

# ---------------------------------------------------------------------------
# 4. Install
# ---------------------------------------------------------------------------
echo "==> Removing any old install..."
${SSH} ${SSH_OPTS} "${TARGET}" "pkg delete -y '${PORTNAME}' 2>/dev/null || true"

echo "==> Installing ${PKGNAME}.pkg..."
${SSH} ${SSH_OPTS} "${TARGET}" "pkg add /tmp/'${PKGNAME}'.pkg && rm -f /tmp/'${PKGNAME}'.pkg"

# ---------------------------------------------------------------------------
# 5. Register with pfSense (menu entry + config.xml record)
# ---------------------------------------------------------------------------
echo "==> Registering with pfSense..."
${SSH} ${SSH_OPTS} "${TARGET}" "php -r \"
    require_once('/etc/inc/config.inc');
    require_once('/etc/inc/util.inc');
    require_once('/usr/local/pkg/speedtest.inc');
    speedtest_install();
    echo 'Registration: OK' . PHP_EOL;
\""

echo ""
echo "==> Done. Open: https://${HOST}/speedtest/speedtest.php"
