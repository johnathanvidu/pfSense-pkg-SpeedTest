<?php
/*
 * speedtest.php - Web UI for pfSense-pkg-speedtest
 *
 * Three-tab interface: Dashboard (run now + latest result),
 * History (last 14 tests), Settings (cron schedule + EULA).
 *
 * Speedtest is a trademark of Ookla, LLC. Results displayed with attribution.
 */

require_once('guiconfig.inc');
require_once('/usr/local/pkg/speedtest.inc');

$input_errors = [];
$savemsg      = '';

// ---------------------------------------------------------------------------
// AJAX / JSON action endpoints — return JSON and exit immediately
// ---------------------------------------------------------------------------

$action = $_REQUEST['action'] ?? '';

if ($action === 'poll_status') {
	header('Content-Type: application/json; charset=utf-8');
	echo json_encode(speedtest_poll_status());
	exit;
}

if ($action === 'run_test' && $_SERVER['REQUEST_METHOD'] === 'POST') {
	header('Content-Type: application/json; charset=utf-8');
	echo json_encode(speedtest_start_async());
	exit;
}

// ---------------------------------------------------------------------------
// Form POST: save settings
// ---------------------------------------------------------------------------

if ($action === 'save_settings' && $_SERVER['REQUEST_METHOD'] === 'POST') {
	speedtest_validate_input($_POST, $input_errors);
	if (empty($input_errors)) {
		speedtest_save_config($_POST);
		$savemsg = gettext('Settings saved successfully.');
	}
}

// ---------------------------------------------------------------------------
// Page data
// ---------------------------------------------------------------------------

$cfg        = speedtest_get_config();
$history    = speedtest_get_history();
$latest     = $history[0] ?? null;
$is_running = speedtest_is_running();
$active_tab = $_GET['tab'] ?? 'dashboard';

$pgtitle    = [gettext('Services'), gettext('Speed Test')];
$shortcut_section = 'speedtest';

include('head.inc');
?>

<div class="panel panel-default">
	<div class="panel-heading">
		<ul class="nav nav-tabs" role="tablist" id="speedtest-tabs">
			<li role="presentation"<?= $active_tab === 'dashboard' ? ' class="active"' : '' ?>>
				<a href="?tab=dashboard"><?= gettext('Dashboard') ?></a>
			</li>
			<li role="presentation"<?= $active_tab === 'history' ? ' class="active"' : '' ?>>
				<a href="?tab=history"><?= gettext('History') ?></a>
			</li>
			<li role="presentation"<?= $active_tab === 'settings' ? ' class="active"' : '' ?>>
				<a href="?tab=settings"><?= gettext('Settings') ?></a>
			</li>
		</ul>
	</div>

<?php if ($active_tab === 'dashboard'): ?>
<!-- ========== DASHBOARD TAB ========== -->
	<div class="panel-body">

		<?php if (empty($cfg['accept_license'])): ?>
		<div class="alert alert-warning">
			<i class="fa fa-exclamation-triangle"></i>
			<?= gettext('You must accept the Ookla License Agreement in the') ?>
			<a href="?tab=settings"><?= gettext('Settings') ?></a>
			<?= gettext('tab before running a speed test.') ?>
		</div>
		<?php endif; ?>

		<!-- Status bar -->
		<div id="speedtest-status-bar" class="alert <?= $is_running ? 'alert-info' : 'alert-default' ?>" style="<?= $is_running ? '' : 'display:none' ?>">
			<i class="fa fa-spinner fa-spin"></i> <?= gettext('Speed test in progress&hellip;') ?>
		</div>

		<!-- Run Now button -->
		<form id="run-test-form" method="post" action="?tab=dashboard">
			<input type="hidden" name="action" value="run_test">
			<input type="hidden" name="__csrf_magic" value="<?= csrf_get_tokens() ?>">
			<button type="submit" id="run-now-btn" class="btn btn-primary"
			        <?= ($is_running || empty($cfg['accept_license'])) ? 'disabled' : '' ?>>
				<i class="fa fa-tachometer"></i> <?= gettext('Run Speed Test Now') ?>
			</button>
			<?php if (!empty($cfg['enable_cron'])): ?>
			<span class="text-muted" style="margin-left:12px">
				<i class="fa fa-clock-o"></i>
				<?= gettext('Scheduled:') ?>
				<?php
				$labels = [
					'hourly'   => gettext('Every Hour'),
					'6hourly'  => gettext('Every 6 Hours'),
					'12hourly' => gettext('Every 12 Hours'),
					'daily'    => gettext('Once Daily (3 AM)'),
					'custom'   => htmlspecialchars($cfg['cron_custom']),
				];
				echo $labels[$cfg['cron_schedule']] ?? $cfg['cron_schedule'];
				?>
			</span>
			<?php endif; ?>
		</form>

		<!-- Running spinner / progress -->
		<div id="running-indicator" style="display:<?= $is_running ? 'block' : 'none' ?>; margin-top:24px; text-align:center; padding:40px 0;">
			<i class="fa fa-spinner fa-spin fa-3x" style="color:#337ab7"></i>
			<p style="margin-top:16px; color:#555"><?= gettext('Running speed test, please wait (10&ndash;30 seconds)&hellip;') ?></p>
		</div>

		<!-- Latest result card -->
		<div id="latest-result-panel" style="display:<?= ($latest && !$is_running) ? 'block' : 'none' ?>; margin-top:24px;">
			<div class="panel panel-default">
				<div class="panel-heading">
					<h3 class="panel-title">
						<i class="fa fa-tachometer"></i> <?= gettext('Latest Result') ?>
						<?php if ($latest): ?>
						<small class="text-muted" style="margin-left:10px">
							<span id="result-timestamp"><?= htmlspecialchars($latest['timestamp'] ?? '') ?></span>
						</small>
						<?php endif; ?>
					</h3>
				</div>
				<div class="panel-body">
					<div class="row text-center">
						<div class="col-sm-3">
							<div style="padding:16px; border-right:1px solid #eee">
								<p style="font-size:13px; color:#777; margin:0"><i class="fa fa-arrow-down" style="color:#5cb85c"></i> <?= gettext('DOWNLOAD') ?></p>
								<p class="lead" style="font-size:32px; margin:4px 0" id="result-download">
									<?= $latest ? htmlspecialchars($latest['download_mbps']) : '&mdash;' ?>
								</p>
								<p style="font-size:12px; color:#aaa; margin:0">Mbps</p>
							</div>
						</div>
						<div class="col-sm-3">
							<div style="padding:16px; border-right:1px solid #eee">
								<p style="font-size:13px; color:#777; margin:0"><i class="fa fa-arrow-up" style="color:#f0ad4e"></i> <?= gettext('UPLOAD') ?></p>
								<p class="lead" style="font-size:32px; margin:4px 0" id="result-upload">
									<?= $latest ? htmlspecialchars($latest['upload_mbps']) : '&mdash;' ?>
								</p>
								<p style="font-size:12px; color:#aaa; margin:0">Mbps</p>
							</div>
						</div>
						<div class="col-sm-3">
							<div style="padding:16px; border-right:1px solid #eee">
								<p style="font-size:13px; color:#777; margin:0"><i class="fa fa-clock-o" style="color:#5bc0de"></i> <?= gettext('PING') ?></p>
								<p class="lead" style="font-size:32px; margin:4px 0" id="result-ping">
									<?= $latest ? htmlspecialchars($latest['ping_ms']) : '&mdash;' ?>
								</p>
								<p style="font-size:12px; color:#aaa; margin:0">ms</p>
							</div>
						</div>
						<div class="col-sm-3">
							<div style="padding:16px">
								<p style="font-size:13px; color:#777; margin:0"><i class="fa fa-random" style="color:#9b59b6"></i> <?= gettext('JITTER') ?></p>
								<p class="lead" style="font-size:32px; margin:4px 0" id="result-jitter">
									<?= $latest ? htmlspecialchars($latest['jitter_ms']) : '&mdash;' ?>
								</p>
								<p style="font-size:12px; color:#aaa; margin:0">ms</p>
							</div>
						</div>
					</div>
					<?php if ($latest): ?>
					<hr style="margin:12px 0">
					<div style="font-size:13px; color:#555">
						<?php if (!empty($latest['server'])): ?>
						<p style="margin:4px 0"><i class="fa fa-server"></i> <strong><?= gettext('Server:') ?></strong> <span id="result-server"><?= htmlspecialchars($latest['server']) ?></span></p>
						<?php endif; ?>
						<?php if (!empty($latest['isp'])): ?>
						<p style="margin:4px 0"><i class="fa fa-globe"></i> <strong><?= gettext('ISP:') ?></strong> <span id="result-isp"><?= htmlspecialchars($latest['isp']) ?></span></p>
						<?php endif; ?>
						<?php if (!empty($latest['result_url'])): ?>
						<p style="margin:4px 0">
							<i class="fa fa-external-link"></i>
							<a href="<?= htmlspecialchars($latest['result_url']) ?>" id="result-url" target="_blank" rel="noopener noreferrer">
								<?= gettext('View full result on Speedtest.net') ?>
							</a>
							<small class="text-muted"><?= gettext('(Powered by Ookla&reg;)') ?></small>
						</p>
						<?php endif; ?>
					</div>
					<?php endif; ?>
				</div>
			</div>
		</div>

		<!-- Error display (populated by JS) -->
		<div id="error-panel" class="alert alert-danger" style="display:none; margin-top:16px">
			<i class="fa fa-exclamation-circle"></i> <span id="error-message"></span>
		</div>

	</div><!-- /panel-body dashboard -->

<?php elseif ($active_tab === 'history'): ?>
<!-- ========== HISTORY TAB ========== -->
	<div class="panel-body">
		<?php if (empty($history)): ?>
		<div class="alert alert-warning">
			<i class="fa fa-info-circle"></i>
			<?= gettext('No speed test history yet. Run a test from the Dashboard tab.') ?>
		</div>
		<?php else: ?>
		<div class="table-responsive">
			<table class="table table-striped table-hover">
				<thead>
					<tr>
						<th><?= gettext('Timestamp') ?></th>
						<th><?= gettext('Download (Mbps)') ?></th>
						<th><?= gettext('Upload (Mbps)') ?></th>
						<th><?= gettext('Ping (ms)') ?></th>
						<th><?= gettext('Jitter (ms)') ?></th>
						<th><?= gettext('Server') ?></th>
						<th><?= gettext('ISP') ?></th>
						<th><?= gettext('Result') ?></th>
					</tr>
				</thead>
				<tbody>
					<?php foreach ($history as $entry): ?>
					<tr>
						<td style="white-space:nowrap"><?= htmlspecialchars($entry['timestamp'] ?? '') ?></td>
						<td><strong><?= htmlspecialchars((string)($entry['download_mbps'] ?? '')) ?></strong></td>
						<td><strong><?= htmlspecialchars((string)($entry['upload_mbps'] ?? '')) ?></strong></td>
						<td><?= htmlspecialchars((string)($entry['ping_ms'] ?? '')) ?></td>
						<td><?= htmlspecialchars((string)($entry['jitter_ms'] ?? '')) ?></td>
						<td><?= htmlspecialchars($entry['server'] ?? '') ?></td>
						<td><?= htmlspecialchars($entry['isp'] ?? '') ?></td>
						<td>
							<?php if (!empty($entry['result_url'])): ?>
							<a href="<?= htmlspecialchars($entry['result_url']) ?>" target="_blank" rel="noopener noreferrer">
								<?= gettext('View') ?>
							</a>
							<?php else: ?>
							&mdash;
							<?php endif; ?>
						</td>
					</tr>
					<?php endforeach; ?>
				</tbody>
			</table>
		</div>
		<p class="text-muted" style="font-size:12px; margin-top:8px">
			<?= sprintf(
				gettext('Showing %d of %d maximum stored results. Results provided by Ookla&reg; Speedtest.'),
				count($history),
				SPEEDTEST_HISTORY_MAX
			) ?>
		</p>
		<?php endif; ?>
	</div><!-- /panel-body history -->

<?php elseif ($active_tab === 'settings'): ?>
<!-- ========== SETTINGS TAB ========== -->
	<div class="panel-body">
		<?php if ($savemsg): ?>
		<div class="alert alert-success">
			<i class="fa fa-check-circle"></i> <?= htmlspecialchars($savemsg) ?>
		</div>
		<?php endif; ?>
		<?php if (!empty($input_errors)): ?>
		<div class="alert alert-danger">
			<ul style="margin:0; padding-left:20px">
				<?php foreach ($input_errors as $e): ?>
				<li><?= htmlspecialchars($e) ?></li>
				<?php endforeach; ?>
			</ul>
		</div>
		<?php endif; ?>

		<form method="post" action="?tab=settings" class="form-horizontal">
			<input type="hidden" name="action" value="save_settings">
			<input type="hidden" name="__csrf_magic" value="<?= csrf_get_tokens() ?>">

			<!-- Accept Ookla EULA -->
			<div class="form-group">
				<label class="col-sm-3 control-label"><?= gettext('Accept Ookla License') ?></label>
				<div class="col-sm-9">
					<input type="checkbox" name="accept_license" value="yes"
					       <?= !empty($cfg['accept_license']) ? 'checked' : '' ?>>
					<span class="help-block" style="margin-top:4px">
						<?= gettext('I accept the') ?>
						<a href="https://www.speedtest.net/about/eula" target="_blank" rel="noopener noreferrer"><?= gettext('Ookla End User License Agreement') ?></a>
						<?= gettext('and') ?>
						<a href="https://www.speedtest.net/about/privacy" target="_blank" rel="noopener noreferrer"><?= gettext('Privacy Policy') ?></a>.
						<?= gettext('Required before any speed test can run.') ?>
					</span>
				</div>
			</div>

			<hr>

			<!-- Enable scheduled tests -->
			<div class="form-group">
				<label class="col-sm-3 control-label"><?= gettext('Enable Scheduled Tests') ?></label>
				<div class="col-sm-9">
					<input type="checkbox" name="enable_cron" value="yes" id="enable-cron"
					       <?= !empty($cfg['enable_cron']) ? 'checked' : '' ?>>
					<span class="help-block"><?= gettext('Automatically run a speed test on the configured schedule.') ?></span>
				</div>
			</div>

			<!-- Schedule selector -->
			<div class="form-group" id="cron-fields" style="display:<?= !empty($cfg['enable_cron']) ? 'block' : 'none' ?>">
				<label class="col-sm-3 control-label"><?= gettext('Schedule') ?></label>
				<div class="col-sm-9">
					<select name="cron_schedule" class="form-control" id="cron-schedule" style="max-width:280px">
						<?php
						$opts = [
							'hourly'   => gettext('Every Hour'),
							'6hourly'  => gettext('Every 6 Hours'),
							'12hourly' => gettext('Every 12 Hours'),
							'daily'    => gettext('Once Daily (3 AM)'),
							'custom'   => gettext('Custom (minute hour)'),
						];
						foreach ($opts as $val => $label):
						?>
						<option value="<?= $val ?>" <?= $cfg['cron_schedule'] === $val ? 'selected' : '' ?>>
							<?= $label ?>
						</option>
						<?php endforeach; ?>
					</select>
				</div>
			</div>

			<!-- Custom cron expression (shown only when "custom" selected) -->
			<div class="form-group" id="custom-cron-group"
			     style="display:<?= (!empty($cfg['enable_cron']) && $cfg['cron_schedule'] === 'custom') ? 'block' : 'none' ?>">
				<label class="col-sm-3 control-label"><?= gettext('Custom Schedule') ?></label>
				<div class="col-sm-9">
					<input type="text" name="cron_custom" class="form-control" style="max-width:200px"
					       placeholder="<?= gettext('e.g. 30 */4') ?>"
					       value="<?= htmlspecialchars($cfg['cron_custom']) ?>">
					<span class="help-block">
						<?= gettext('Enter minute and hour fields only (e.g., <code>30 */4</code> = every 4 hours at :30). Day, month, and weekday are always <code>*</code>.') ?>
					</span>
				</div>
			</div>

			<hr>

			<!-- Optional server ID -->
			<div class="form-group">
				<label class="col-sm-3 control-label"><?= gettext('Speedtest Server ID') ?></label>
				<div class="col-sm-9">
					<input type="text" name="server_id" class="form-control" style="max-width:160px"
					       placeholder="<?= gettext('Auto-select') ?>"
					       value="<?= htmlspecialchars($cfg['server_id']) ?>">
					<span class="help-block">
						<?= gettext('Optional Ookla server ID to pin tests to a specific server. Leave blank to auto-select the closest server. Find IDs by running <code>speedtest --servers</code> in the shell.') ?>
					</span>
				</div>
			</div>

			<div class="form-group">
				<div class="col-sm-offset-3 col-sm-9">
					<button type="submit" class="btn btn-primary">
						<i class="fa fa-save"></i> <?= gettext('Save Settings') ?>
					</button>
				</div>
			</div>

		</form>
	</div><!-- /panel-body settings -->
<?php endif; ?>

</div><!-- /panel -->

<?php include('foot.inc'); ?>

<script type="text/javascript">
//<![CDATA[

var CSRF_NAME  = '__csrf_magic';
var CSRF_VALUE = <?= json_encode(csrf_get_tokens()) ?>;
var IS_RUNNING = <?= $is_running ? 'true' : 'false' ?>;
var HAS_LICENSE = <?= !empty($cfg['accept_license']) ? 'true' : 'false' ?>;

// ---------------------------------------------------------------------------
// Dashboard polling
// ---------------------------------------------------------------------------

var pollInterval = null;

function startPolling() {
	if (pollInterval) return;
	document.getElementById('running-indicator').style.display = 'block';
	var sb = document.getElementById('speedtest-status-bar');
	if (sb) {
		sb.className = 'alert alert-info';
		sb.style.display = 'block';
	}
	var btn = document.getElementById('run-now-btn');
	if (btn) btn.disabled = true;
	var ep = document.getElementById('error-panel');
	if (ep) ep.style.display = 'none';

	pollInterval = setInterval(doPoll, 2000);
}

function stopPolling() {
	if (pollInterval) {
		clearInterval(pollInterval);
		pollInterval = null;
	}
	document.getElementById('running-indicator').style.display = 'none';
	var btn = document.getElementById('run-now-btn');
	if (btn) btn.disabled = !HAS_LICENSE;
}

function doPoll() {
	fetch('?action=poll_status', { credentials: 'same-origin' })
		.then(function(r) { return r.json(); })
		.then(function(data) {
			if (data.status === 'running') return; // keep polling

			stopPolling();
			var sb = document.getElementById('speedtest-status-bar');

			if (data.status === 'complete') {
				renderResult(data.result);
				if (sb) {
					sb.className = 'alert alert-success';
					sb.innerHTML = '<i class="fa fa-check-circle"></i> Speed test completed successfully.';
				}
			} else if (data.status === 'error') {
				if (sb) sb.style.display = 'none';
				var ep = document.getElementById('error-panel');
				if (ep) {
					document.getElementById('error-message').textContent =
						data.message || 'Unknown error.';
					ep.style.display = 'block';
				}
			} else {
				// idle — test finished before first poll; reload to sync page state
				if (sb) sb.style.display = 'none';
				window.location.reload();
			}
		})
		.catch(function(err) {
			stopPolling();
			var sb = document.getElementById('speedtest-status-bar');
			if (sb) {
				sb.className = 'alert alert-danger';
				sb.innerHTML = '<i class="fa fa-exclamation-circle"></i> Poll error: ' + err;
			}
		});
}

function renderResult(r) {
	function setText(id, val) {
		var el = document.getElementById(id);
		if (el) el.textContent = val;
	}
	setText('result-download',  r.download_mbps);
	setText('result-upload',    r.upload_mbps);
	setText('result-ping',      r.ping_ms);
	setText('result-jitter',    r.jitter_ms);
	setText('result-server',    r.server || '');
	setText('result-isp',       r.isp || '');
	setText('result-timestamp', r.timestamp || '');

	var urlEl = document.getElementById('result-url');
	if (urlEl && r.result_url) {
		urlEl.href = r.result_url;
		urlEl.parentElement.style.display = '';
	}

	var panel = document.getElementById('latest-result-panel');
	if (panel) panel.style.display = 'block';
}

// Intercept Run Now form → AJAX POST
var runForm = document.getElementById('run-test-form');
if (runForm) {
	runForm.addEventListener('submit', function(e) {
		e.preventDefault();

		var fd = new FormData();
		fd.append('action', 'run_test');
		fd.append(CSRF_NAME, CSRF_VALUE);

		fetch(window.location.pathname + '?tab=dashboard', {
			method: 'POST',
			credentials: 'same-origin',
			body: fd
		})
		.then(function(r) { return r.json(); })
		.then(function(data) {
			if (data.status === 'started' || data.status === 'already_running') {
				startPolling();
			} else {
				var sb = document.getElementById('speedtest-status-bar');
				if (sb) {
					sb.className = 'alert alert-danger';
					sb.innerHTML = '<i class="fa fa-exclamation-circle"></i> ' +
						'Could not start test: ' + (data.message || 'Unknown error.');
					sb.style.display = 'block';
				}
			}
		})
		.catch(function(err) {
			var sb = document.getElementById('speedtest-status-bar');
			if (sb) {
				sb.className = 'alert alert-danger';
				sb.innerHTML = '<i class="fa fa-exclamation-circle"></i> Request error: ' + err;
				sb.style.display = 'block';
			}
		});
	});
}

// Auto-start polling if a test was running when the page loaded
if (IS_RUNNING) {
	startPolling();
}

// ---------------------------------------------------------------------------
// Settings tab: toggle cron fields visibility
// ---------------------------------------------------------------------------

var enableCronCb = document.getElementById('enable-cron');
if (enableCronCb) {
	enableCronCb.addEventListener('change', function() {
		var fields = document.getElementById('cron-fields');
		if (fields) fields.style.display = this.checked ? 'block' : 'none';
		updateCustomCronVisibility();
	});
}

var cronScheduleSel = document.getElementById('cron-schedule');
if (cronScheduleSel) {
	cronScheduleSel.addEventListener('change', updateCustomCronVisibility);
}

function updateCustomCronVisibility() {
	var sel = document.getElementById('cron-schedule');
	var cb  = document.getElementById('enable-cron');
	var grp = document.getElementById('custom-cron-group');
	if (grp && sel && cb) {
		grp.style.display = (cb.checked && sel.value === 'custom') ? 'block' : 'none';
	}
}

//]]>
</script>
