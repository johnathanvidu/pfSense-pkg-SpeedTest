<?php
/*
 * speedtest.inc - Backend library for pfSense-pkg-speedtest
 *
 * Provides config management, async test execution, result formatting,
 * history persistence, and cron scheduling for the Speed Test package.
 *
 * Uses the Ookla Speedtest CLI (net/ookla-speedtest).
 * Speedtest is a trademark of Ookla, LLC. Used with attribution.
 */

define('SPEEDTEST_HISTORY_FILE', '/var/db/speedtest/history.json');
define('SPEEDTEST_CURRENT_FILE', '/var/db/speedtest/current.json');
define('SPEEDTEST_PID_FILE',     '/var/run/speedtest_running.pid');
define('SPEEDTEST_HISTORY_MAX',  14);
define('SPEEDTEST_BINARY',       '/usr/local/bin/speedtest');
define('SPEEDTEST_RUNNER',       '/usr/local/bin/speedtest_runner.sh');

/*
 * Return current package config merged with defaults.
 */
function speedtest_get_config(): array {
	$cfg = config_get_path('installedpackages/speedtest/config/0', []);
	return array_merge([
		'enable_cron'    => '',
		'cron_schedule'  => 'daily',
		'cron_custom'    => '',
		'accept_license' => '',
		'server_id'      => '',
	], $cfg);
}

/*
 * Save POSTed settings to config.xml and sync cron.
 */
function speedtest_save_config(array $post): void {
	$cfg = [
		'enable_cron'    => !empty($post['enable_cron'])    ? 'yes' : '',
		'cron_schedule'  => $post['cron_schedule'] ?? 'daily',
		'cron_custom'    => trim($post['cron_custom'] ?? ''),
		'accept_license' => !empty($post['accept_license']) ? 'yes' : '',
		'server_id'      => trim($post['server_id'] ?? ''),
	];
	config_set_path('installedpackages/speedtest/config/0', $cfg);
	write_config('pfSense-pkg-speedtest: settings saved');
	speedtest_sync_cron($cfg);
}

/*
 * Map schedule name to [minute, hour] crontab fields and register/remove job.
 */
function speedtest_sync_cron(array $cfg): void {
	$schedules = [
		'hourly'   => ['0',  '*'],
		'6hourly'  => ['0',  '*/6'],
		'12hourly' => ['0',  '*/12'],
		'daily'    => ['0',  '3'],
	];

	if (empty($cfg['enable_cron'])) {
		install_cron_job(SPEEDTEST_RUNNER, false);
		return;
	}

	if ($cfg['cron_schedule'] === 'custom') {
		$parts = preg_split('/\s+/', trim($cfg['cron_custom']));
		$min  = $parts[0] ?? '0';
		$hour = $parts[1] ?? '3';
	} else {
		[$min, $hour] = $schedules[$cfg['cron_schedule']] ?? $schedules['daily'];
	}

	install_cron_job(SPEEDTEST_RUNNER, true, $min, $hour, '*', '*', '*', 'root');
}

/*
 * Check if a speedtest is currently running by PID file + process existence.
 */
function speedtest_is_running(): bool {
	if (!file_exists(SPEEDTEST_PID_FILE)) {
		return false;
	}
	$pid = (int)trim(file_get_contents(SPEEDTEST_PID_FILE));
	if ($pid <= 0) {
		return false;
	}
	return posix_kill($pid, 0);
}

/*
 * Fork speedtest_runner.sh in background and return status array.
 */
function speedtest_start_async(): array {
	if (speedtest_is_running()) {
		return ['status' => 'already_running'];
	}

	// Clear any stale result from a previous run
	@unlink(SPEEDTEST_CURRENT_FILE);

	// nohup detaches from PHP's process group; we capture the child PID via echo $!
	$cmd = 'nohup ' . SPEEDTEST_RUNNER . ' > /dev/null 2>&1 & echo $!';
	$pid = (int)trim(shell_exec($cmd));

	if ($pid <= 0) {
		log_error('pfSense-pkg-speedtest: failed to fork speedtest_runner.sh');
		return ['status' => 'error', 'message' => 'Failed to start speedtest process.'];
	}

	file_put_contents(SPEEDTEST_PID_FILE, (string)$pid);
	log_error("pfSense-pkg-speedtest: on-demand test started (PID {$pid})");

	return ['status' => 'started', 'pid' => $pid];
}

/*
 * Poll test status — called by AJAX every 2 seconds.
 * Returns: {status: running|complete|error|idle, result?: array, message?: string}
 */
function speedtest_poll_status(): array {
	if (speedtest_is_running()) {
		return ['status' => 'running'];
	}

	if (!file_exists(SPEEDTEST_CURRENT_FILE)) {
		return ['status' => 'idle'];
	}

	$raw  = @file_get_contents(SPEEDTEST_CURRENT_FILE);
	$data = json_decode($raw, true);

	if (!is_array($data)) {
		return ['status' => 'error', 'message' => 'Could not parse speedtest output.'];
	}

	if (isset($data['error'])) {
		return ['status' => 'error', 'message' => $data['error']];
	}

	if (!isset($data['download'])) {
		return ['status' => 'error', 'message' => 'Incomplete result from speedtest binary.'];
	}

	return ['status' => 'complete', 'result' => speedtest_format_result($data)];
}

/*
 * Convert raw Ookla JSON output to a display-ready associative array.
 *
 * Ookla reports bandwidth in bytes/sec; multiply by 8 / 1_000_000 for Mbps
 * using SI units (matches how Ookla.com displays results).
 */
function speedtest_format_result(array $raw): array {
	return [
		'timestamp'      => $raw['timestamp'] ?? date('c'),
		'download_mbps'  => round(($raw['download']['bandwidth'] ?? 0) * 8 / 1_000_000, 2),
		'upload_mbps'    => round(($raw['upload']['bandwidth']   ?? 0) * 8 / 1_000_000, 2),
		'ping_ms'        => round($raw['ping']['latency'] ?? 0, 1),
		'jitter_ms'      => round($raw['ping']['jitter']  ?? 0, 1),
		'server'         => trim(($raw['server']['name'] ?? '') . ', ' . ($raw['server']['location'] ?? ''), ', '),
		'isp'            => $raw['isp'] ?? '',
		'result_url'     => $raw['result']['url'] ?? '',
	];
}

/*
 * Return history array (newest first), or empty array if no history file.
 */
function speedtest_get_history(): array {
	if (!file_exists(SPEEDTEST_HISTORY_FILE)) {
		return [];
	}
	$raw = @file_get_contents(SPEEDTEST_HISTORY_FILE);
	return json_decode($raw, true) ?? [];
}

/*
 * Prepend a formatted result to history, trim to SPEEDTEST_HISTORY_MAX, write atomically.
 */
function speedtest_append_history(array $result): void {
	$dir = dirname(SPEEDTEST_HISTORY_FILE);
	if (!is_dir($dir)) {
		mkdir($dir, 0750, true);
	}

	$history = speedtest_get_history();
	array_unshift($history, $result);
	$history = array_slice($history, 0, SPEEDTEST_HISTORY_MAX);

	file_put_contents(
		SPEEDTEST_HISTORY_FILE,
		json_encode($history, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES),
		LOCK_EX
	);
}

/*
 * Package install hook — create runtime directory and register with pfSense.
 *
 * Registers the package in installedpackages/package (so pfSense recognises it)
 * and adds the Services menu entry to installedpackages/menu (so the navbar
 * shows "Services > Speed Test").  Safe to call multiple times — duplicate
 * entries are removed before inserting.
 */
function speedtest_install(): void {
	// Create runtime data directory
	$dir = dirname(SPEEDTEST_HISTORY_FILE);
	if (!is_dir($dir)) {
		mkdir($dir, 0750, true);
	}

	// Register in installedpackages/package
	$packages = config_get_path('installedpackages/package', []);
	foreach ($packages as $i => $p) {
		if (($p['internal_name'] ?? '') === 'speedtest') {
			unset($packages[$i]);
		}
	}
	$packages   = array_values($packages);
	$packages[] = [
		'name'          => 'speedtest',
		'internal_name' => 'speedtest',
		'version'       => '1.0.0',
		'configfile'    => 'speedtest.xml',
	];
	config_set_path('installedpackages/package', $packages);

	// Register Services menu entry in installedpackages/menu
	init_config_arr(['installedpackages', 'menu']);
	$menus = config_get_path('installedpackages/menu', []);
	foreach ($menus as $i => $m) {
		if (($m['name'] ?? '') === 'Speed Test') {
			unset($menus[$i]);
		}
	}
	$menus   = array_values($menus);
	$menus[] = [
		'name'        => 'Speed Test',
		'tooltiptext' => 'Run and schedule internet speed tests via Ookla Speedtest CLI',
		'section'     => 'Services',
		'url'         => '/speedtest/speedtest.php',
	];
	config_set_path('installedpackages/menu', $menus);

	write_config('pfSense-pkg-speedtest: package installed');
	log_error('pfSense-pkg-speedtest: package installed');
}

/*
 * Package deinstall hook — remove menu entry, package registration, cron job,
 * and package config tree.
 * History files at /var/db/speedtest/ are intentionally preserved (user data).
 */
function speedtest_deinstall(): void {
	// Remove Services menu entry
	$menus = config_get_path('installedpackages/menu', []);
	foreach ($menus as $i => $m) {
		if (($m['name'] ?? '') === 'Speed Test') {
			unset($menus[$i]);
		}
	}
	config_set_path('installedpackages/menu', array_values($menus));

	// Remove package registration
	$packages = config_get_path('installedpackages/package', []);
	foreach ($packages as $i => $p) {
		if (($p['internal_name'] ?? '') === 'speedtest') {
			unset($packages[$i]);
		}
	}
	config_set_path('installedpackages/package', array_values($packages));

	install_cron_job(SPEEDTEST_RUNNER, false);
	config_del_path('installedpackages/speedtest');
	write_config('pfSense-pkg-speedtest: package removed');
	log_error('pfSense-pkg-speedtest: package removed');
}

/*
 * Validate Settings form input. Populates $input_errors by reference.
 */
function speedtest_validate_input(array $post, array &$input_errors): void {
	if (!empty($post['enable_cron']) && ($post['cron_schedule'] ?? '') === 'custom') {
		$custom = trim($post['cron_custom'] ?? '');
		if (!preg_match('/^\S+\s+\S+$/', $custom)) {
			$input_errors[] = gettext(
				'Custom cron schedule must be two whitespace-separated fields: "minute hour" ' .
				'(e.g., "30 */4" for every 4 hours at :30).'
			);
		}
	}
}
