#!/bin/sh
#
# speedtest_runner.sh - Execute Ookla Speedtest CLI and persist results
#
# Called either on-demand (via speedtest.php AJAX) or by cron.
# Writes JSON to /var/db/speedtest/current.json on every run.
# Appends formatted result to /var/db/speedtest/history.json on success.
#
# Speedtest is a trademark of Ookla, LLC.
#

set -e

SPEEDTEST_BIN="/usr/local/bin/speedtest"
CURRENT_FILE="/var/db/speedtest/current.json"
HISTORY_FILE="/var/db/speedtest/history.json"
PID_FILE="/var/run/speedtest_running.pid"
STDERR_TMP="/tmp/speedtest_stderr_$$.tmp"
LOG_TAG="pfSense-pkg-speedtest"
PHP="/usr/local/bin/php"

# ---------------------------------------------------------------------------
# PID management — write our PID immediately; trap ensures cleanup on exit
# ---------------------------------------------------------------------------

echo $$ > "${PID_FILE}"
trap 'rm -f "${PID_FILE}" "${STDERR_TMP}"' EXIT INT TERM

# ---------------------------------------------------------------------------
# Ensure output directory exists
# ---------------------------------------------------------------------------

mkdir -p "$(dirname "${CURRENT_FILE}")"

# ---------------------------------------------------------------------------
# Read configuration from pfSense config.xml via PHP
# ---------------------------------------------------------------------------

ACCEPT_LICENSE=$(${PHP} -r "
    require_once('/etc/inc/config.inc');
    \$c = config_get_path('installedpackages/speedtest/config/0', []);
    echo !empty(\$c['accept_license']) ? '1' : '0';
" 2>/dev/null)

SERVER_ID=$(${PHP} -r "
    require_once('/etc/inc/config.inc');
    \$c = config_get_path('installedpackages/speedtest/config/0', []);
    echo trim(\$c['server_id'] ?? '');
" 2>/dev/null)

# ---------------------------------------------------------------------------
# Bail early if EULA not accepted
# ---------------------------------------------------------------------------

if [ "${ACCEPT_LICENSE}" != "1" ]; then
    printf '{"error":"Ookla license not accepted. Go to Services \u203a Speed Test \u203a Settings."}\n' \
        > "${CURRENT_FILE}"
    logger -t "${LOG_TAG}" "Aborted: Ookla license not accepted."
    exit 1
fi

# ---------------------------------------------------------------------------
# Build speedtest arguments
# ---------------------------------------------------------------------------

ARGS="--format=json --accept-license --accept-gdpr"

if [ -n "${SERVER_ID}" ]; then
    ARGS="${ARGS} --server-id=${SERVER_ID}"
fi

# ---------------------------------------------------------------------------
# Run the speedtest binary
# ---------------------------------------------------------------------------

logger -t "${LOG_TAG}" "Starting speed test (args: ${ARGS})"

if "${SPEEDTEST_BIN}" ${ARGS} > "${CURRENT_FILE}" 2>"${STDERR_TMP}"; then

    # Validate that the output contains a 'download' key
    if ${PHP} -r "
        \$d = json_decode(file_get_contents('${CURRENT_FILE}'), true);
        exit(isset(\$d['download']) ? 0 : 1);
    " 2>/dev/null; then

        logger -t "${LOG_TAG}" "Speed test completed successfully."

        # Append to history via PHP (handles max-14 trimming and file locking)
        ${PHP} -r "
            require_once('/usr/local/pkg/speedtest.inc');
            \$raw    = json_decode(file_get_contents('${CURRENT_FILE}'), true);
            \$result = speedtest_format_result(\$raw);
            speedtest_append_history(\$result);
        " 2>/dev/null

    else
        logger -t "${LOG_TAG}" "Speed test produced invalid or incomplete JSON."
        printf '{"error":"Speedtest binary produced invalid JSON output."}\n' > "${CURRENT_FILE}"
        exit 1
    fi

else
    # Binary exited non-zero — capture stderr for a useful error message
    ERRMSG=$(cat "${STDERR_TMP}" 2>/dev/null | head -5 | tr -d '\n' | \
             sed "s/'/\\\\'/g; s/\"/\\\\\"/g")

    logger -t "${LOG_TAG}" "Speed test failed: ${ERRMSG}"

    # Write an error JSON that speedtest_poll_status() will surface to the UI
    ${PHP} -r "
        echo json_encode(['error' => 'Speedtest binary failed: ' . trim('${ERRMSG}')]);
    " > "${CURRENT_FILE}" 2>/dev/null || \
        printf '{"error":"Speedtest binary failed (see system log for details)."}\n' \
            > "${CURRENT_FILE}"

    exit 1
fi

# PID file and temp file cleanup handled by trap
exit 0
