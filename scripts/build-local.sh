#!/bin/sh
#
# build-local.sh — Build pfSense-pkg-speedtest.pkg on macOS (no VM needed).
#
# Valid for NO_BUILD + NO_ARCH packages (pure PHP + shell — no compiled code).
# Produces a pkg(8)-compatible archive: tar.xz with +MANIFEST, +COMPACT_MANIFEST,
# and staged files at their absolute installation paths.
#
# Requirements (macOS): tar, xz  (xz: brew install xz if missing)
# Requirements (Linux): tar, xz-utils
#
# Usage (via Makefile): make build
# Usage (direct):       sh scripts/build-local.sh [version]
#

set -e

VERSION="${1:-1.0.0}"
PORTNAME="pfSense-pkg-speedtest"
PKGNAME="${PORTNAME}-${VERSION}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FILES_DIR="${REPO_ROOT}/pfSense-pkg-speedtest/files"
BUILD_DIR="${REPO_ROOT}/_build"
STAGE_DIR="${BUILD_DIR}/stage"
ARCHIVE_DIR="${BUILD_DIR}/archive"
OUTPUT="${REPO_ROOT}/${PKGNAME}.pkg"

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# ---------------------------------------------------------------------------
# Stage files
# The priv file is placed under /usr/local/share/ (within PREFIX).
# A +POST_INSTALL script copies it to /etc/inc/priv/ at pkg-add time.
# ---------------------------------------------------------------------------

echo "==> Staging files..."
rm -rf "${BUILD_DIR}"
mkdir -p \
    "${STAGE_DIR}/usr/local/bin" \
    "${STAGE_DIR}/usr/local/pkg" \
    "${STAGE_DIR}/usr/local/www/speedtest" \
    "${STAGE_DIR}/usr/local/www/widgets/widgets" \
    "${STAGE_DIR}/usr/local/share/${PORTNAME}"

cp "${FILES_DIR}/usr/local/bin/speedtest_runner.sh"                  "${STAGE_DIR}/usr/local/bin/"
cp "${FILES_DIR}/usr/local/pkg/speedtest.inc"                        "${STAGE_DIR}/usr/local/pkg/"
cp "${FILES_DIR}/usr/local/pkg/speedtest.xml"                        "${STAGE_DIR}/usr/local/pkg/"
cp "${FILES_DIR}/usr/local/www/speedtest/speedtest.php"              "${STAGE_DIR}/usr/local/www/speedtest/"
cp "${FILES_DIR}/usr/local/www/widgets/widgets/speedtest.widget.php" "${STAGE_DIR}/usr/local/www/widgets/widgets/"
cp "${FILES_DIR}/etc/inc/priv/speedtest.priv.inc"                    "${STAGE_DIR}/usr/local/share/${PORTNAME}/"

chmod 755 "${STAGE_DIR}/usr/local/bin/speedtest_runner.sh"
chmod 644 \
    "${STAGE_DIR}/usr/local/pkg/speedtest.inc" \
    "${STAGE_DIR}/usr/local/pkg/speedtest.xml" \
    "${STAGE_DIR}/usr/local/www/speedtest/speedtest.php" \
    "${STAGE_DIR}/usr/local/www/widgets/widgets/speedtest.widget.php" \
    "${STAGE_DIR}/usr/local/share/${PORTNAME}/speedtest.priv.inc"

# ---------------------------------------------------------------------------
# Checksums and flatsize
# ---------------------------------------------------------------------------

echo "==> Computing checksums..."

H_RUNNER=$(sha256_file "${STAGE_DIR}/usr/local/bin/speedtest_runner.sh")
H_INC=$(sha256_file    "${STAGE_DIR}/usr/local/pkg/speedtest.inc")
H_XML=$(sha256_file    "${STAGE_DIR}/usr/local/pkg/speedtest.xml")
H_PHP=$(sha256_file    "${STAGE_DIR}/usr/local/www/speedtest/speedtest.php")
H_WIDGET=$(sha256_file "${STAGE_DIR}/usr/local/www/widgets/widgets/speedtest.widget.php")
H_PRIV=$(sha256_file   "${STAGE_DIR}/usr/local/share/${PORTNAME}/speedtest.priv.inc")

FLATSIZE=$(find "${STAGE_DIR}" -type f | xargs wc -c 2>/dev/null | tail -1 | awk '{print $1}')

# ---------------------------------------------------------------------------
# +COMPACT_MANIFEST — metadata only, no scripts/files sections
# ---------------------------------------------------------------------------

mkdir -p "${ARCHIVE_DIR}"

cat > "${ARCHIVE_DIR}/+COMPACT_MANIFEST" <<JSON
{
  "name": "${PORTNAME}",
  "version": "${VERSION}",
  "origin": "sysutils/${PORTNAME}",
  "comment": "pfSense package for Ookla Speedtest CLI",
  "desc": "Integrates the Ookla Speedtest CLI into the pfSense web GUI, providing on-demand and scheduled internet speed testing with history and a dashboard widget.",
  "maintainer": "johnathan.vidu@gmail.com",
  "www": "https://github.com/johnathanvidu/pfSense-pkg-SpeedTest",
  "abi": "FreeBSD:*:*",
  "arch": "freebsd:*:*",
  "prefix": "/usr/local",
  "flatsize": ${FLATSIZE}
}
JSON

# ---------------------------------------------------------------------------
# +MANIFEST — full manifest including scripts and file checksums
#
# Scripts are newline-escaped JSON strings.
# POST_INSTALL: copy priv file to /etc/inc/priv/ (pfSense ACL discovery path)
# PRE_DEINSTALL: remove priv file
# ---------------------------------------------------------------------------

POST_INSTALL='#!/bin/sh\nset -e\nmkdir -p /etc/inc/priv\ncp /usr/local/share/pfSense-pkg-speedtest/speedtest.priv.inc /etc/inc/priv/speedtest.priv.inc\nchmod 644 /etc/inc/priv/speedtest.priv.inc\nmkdir -p /var/db/speedtest\n'
PRE_DEINSTALL='#!/bin/sh\nrm -f /etc/inc/priv/speedtest.priv.inc\n'

cat > "${ARCHIVE_DIR}/+MANIFEST" <<JSON
{
  "name": "${PORTNAME}",
  "version": "${VERSION}",
  "origin": "sysutils/${PORTNAME}",
  "comment": "pfSense package for Ookla Speedtest CLI",
  "desc": "Integrates the Ookla Speedtest CLI into the pfSense web GUI, providing on-demand and scheduled internet speed testing with history and a dashboard widget.",
  "maintainer": "johnathan.vidu@gmail.com",
  "www": "https://github.com/johnathanvidu/pfSense-pkg-SpeedTest",
  "abi": "FreeBSD:*:*",
  "arch": "freebsd:*:*",
  "prefix": "/usr/local",
  "flatsize": ${FLATSIZE},
  "scripts": {
    "post-install": "${POST_INSTALL}",
    "pre-deinstall": "${PRE_DEINSTALL}"
  },
  "files": {
    "usr/local/bin/speedtest_runner.sh":                  "${H_RUNNER}",
    "usr/local/pkg/speedtest.inc":                        "${H_INC}",
    "usr/local/pkg/speedtest.xml":                        "${H_XML}",
    "usr/local/www/speedtest/speedtest.php":              "${H_PHP}",
    "usr/local/www/widgets/widgets/speedtest.widget.php": "${H_WIDGET}",
    "usr/local/share/${PORTNAME}/speedtest.priv.inc":     "${H_PRIV}"
  }
}
JSON

# ---------------------------------------------------------------------------
# Copy staged files into archive, then tar.xz
# COPYFILE_DISABLE=1 suppresses macOS ._AppleDouble sidecar files in the tar
# ---------------------------------------------------------------------------

echo "==> Assembling archive..."
cp -R "${STAGE_DIR}/." "${ARCHIVE_DIR}/"

cd "${ARCHIVE_DIR}"
COPYFILE_DISABLE=1 tar -cJf "${OUTPUT}" \
    "+COMPACT_MANIFEST" \
    "+MANIFEST" \
    "usr/local/bin/speedtest_runner.sh" \
    "usr/local/pkg/speedtest.inc" \
    "usr/local/pkg/speedtest.xml" \
    "usr/local/www/speedtest/speedtest.php" \
    "usr/local/www/widgets/widgets/speedtest.widget.php" \
    "usr/local/share/${PORTNAME}/speedtest.priv.inc"

cd "${REPO_ROOT}"
rm -rf "${BUILD_DIR}"

echo ""
SIZE=$(wc -c < "${OUTPUT}" | tr -d ' ')
echo "==> Built: ${OUTPUT} (${SIZE} bytes)"
