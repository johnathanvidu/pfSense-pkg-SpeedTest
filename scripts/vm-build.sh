#!/bin/sh
#
# vm-build.sh — Build pfSense-pkg-speedtest.pkg inside a FreeBSD 14 VM.
#
# Invoked by the host Makefile via:
#   limactl shell freebsd14 -- sh /tmp/vm-build.sh [version]
#
# Source files are expected at /tmp/pkg-files/ (uploaded by host via limactl cp).
# Output .pkg is written to /tmp/ and downloaded by the host after this script exits.
#
# Requires: FreeBSD 14.0, pkgng (pkg bootstrap done by Lima provisioner)
#

set -e

VERSION="${1:-1.0.0}"
MAINTAINER="${2:-Johnathan Viduchinsky}"
PKG_WWW="${3:-https://github.com/johnathanvidu/pfSense-pkg-SpeedTest}"
PORTNAME="pfSense-pkg-speedtest"
PKGNAME="${PORTNAME}-${VERSION}"
FILES_DIR="/tmp/pkg-files"
OUTPUT_DIR="/tmp"
WORK_DIR="$(mktemp -d -t pkgbuild)"

echo "==> Building ${PKGNAME}.pkg"
echo "    OS:      FreeBSD $(uname -r) ($(uname -m))"
echo "    Source:  ${FILES_DIR}"
echo "    Output:  ${OUTPUT_DIR}/${PKGNAME}.pkg"

# Ensure pkgng is available (provision may not have run yet on manual starts)
if ! pkg -N >/dev/null 2>&1; then
    echo "==> Bootstrapping pkg..."
    ASSUME_ALWAYS_YES=yes pkg bootstrap -f
fi

# ---------------------------------------------------------------------------
# Stage files under the prefix tree (/usr/local)
# The priv file is staged under share/ so it stays within the prefix.
# A +POST_INSTALL script copies it to /etc/inc/priv/ at install time.
# ---------------------------------------------------------------------------

STAGE="${WORK_DIR}/stage"
mkdir -p \
    "${STAGE}/usr/local/bin" \
    "${STAGE}/usr/local/pkg" \
    "${STAGE}/usr/local/www/speedtest" \
    "${STAGE}/usr/local/www/widgets/widgets" \
    "${STAGE}/usr/local/share/${PORTNAME}"

cp "${FILES_DIR}/usr/local/bin/speedtest_runner.sh"                  "${STAGE}/usr/local/bin/"
cp "${FILES_DIR}/usr/local/pkg/speedtest.inc"                        "${STAGE}/usr/local/pkg/"
cp "${FILES_DIR}/usr/local/pkg/speedtest.xml"                        "${STAGE}/usr/local/pkg/"
cp "${FILES_DIR}/usr/local/www/speedtest/speedtest.php"              "${STAGE}/usr/local/www/speedtest/"
cp "${FILES_DIR}/usr/local/www/widgets/widgets/speedtest.widget.php" "${STAGE}/usr/local/www/widgets/widgets/"
cp "${FILES_DIR}/etc/inc/priv/speedtest.priv.inc"                    "${STAGE}/usr/local/share/${PORTNAME}/"

chmod 755 "${STAGE}/usr/local/bin/speedtest_runner.sh"
chmod 644 \
    "${STAGE}/usr/local/pkg/speedtest.inc" \
    "${STAGE}/usr/local/pkg/speedtest.xml" \
    "${STAGE}/usr/local/www/speedtest/speedtest.php" \
    "${STAGE}/usr/local/www/widgets/widgets/speedtest.widget.php" \
    "${STAGE}/usr/local/share/${PORTNAME}/speedtest.priv.inc"

# ---------------------------------------------------------------------------
# Plist: paths relative to PREFIX (/usr/local), as required by pkg create -p
# ---------------------------------------------------------------------------

cat > "${WORK_DIR}/plist" <<PLIST
bin/speedtest_runner.sh
pkg/speedtest.inc
pkg/speedtest.xml
www/speedtest/speedtest.php
www/widgets/widgets/speedtest.widget.php
share/${PORTNAME}/speedtest.priv.inc
PLIST

# ---------------------------------------------------------------------------
# UCL manifest
# abi/arch use wildcards — this is a NO_ARCH package (no compiled code)
# ---------------------------------------------------------------------------

FLATSIZE=$(find "${STAGE}" -type f -exec stat -f '%z' {} \; | awk '{s+=$1} END {print s+0}')

# Scripts are embedded in the UCL manifest using UCL heredoc strings (<<EOD).
# UCL heredoc blocks take their content literally — single quotes, double quotes,
# and backslashes need no escaping.  The shell does NOT interpret <<EOD inside
# <<UCL; it passes the marker through verbatim.
# The -s (scripts dir) flag is not available for `-M manifest` mode in pkg 1.x.

cat > "${WORK_DIR}/manifest.ucl" <<UCL
name = "${PORTNAME}"
version = "${VERSION}"
origin = "sysutils/${PORTNAME}"
comment = "pfSense package for Ookla Speedtest CLI"
maintainer = "${MAINTAINER}"
www = "${PKG_WWW}"
prefix = "/usr/local"
abi = "FreeBSD:*:*"
arch = "freebsd:*:*"
flatsize = ${FLATSIZE}
desc = "Integrates the Ookla Speedtest CLI into the pfSense web GUI, providing on-demand and scheduled internet speed testing with history and a dashboard widget."
scripts {
  post-install = <<EOD
#!/bin/sh
set -e
mkdir -p /etc/inc/priv
cp /usr/local/share/pfSense-pkg-speedtest/speedtest.priv.inc /etc/inc/priv/speedtest.priv.inc
chmod 644 /etc/inc/priv/speedtest.priv.inc
mkdir -p /var/db/speedtest
# Register menu entry and package in pfSense config.xml
/usr/local/bin/php -r 'require_once("/etc/inc/functions.inc"); require_once("/usr/local/pkg/speedtest.inc"); speedtest_install();'
EOD
  pre-deinstall = <<EOD
#!/bin/sh
# Remove menu entry and package registration from pfSense config.xml
/usr/local/bin/php -r 'require_once("/etc/inc/functions.inc"); require_once("/usr/local/pkg/speedtest.inc"); speedtest_deinstall();'
rm -f /etc/inc/priv/speedtest.priv.inc
EOD
}
UCL

# ---------------------------------------------------------------------------
# Build the package using FreeBSD's native pkg create
# ---------------------------------------------------------------------------

echo "==> Running pkg create..."
pkg create \
    -M "${WORK_DIR}/manifest.ucl" \
    -p "${WORK_DIR}/plist" \
    -r "${STAGE}" \
    -o "${OUTPUT_DIR}"

rm -rf "${WORK_DIR}"

echo ""
ls -lh "${OUTPUT_DIR}/${PKGNAME}.pkg"
echo "==> Done: ${OUTPUT_DIR}/${PKGNAME}.pkg"
