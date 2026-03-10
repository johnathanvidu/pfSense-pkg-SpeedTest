<?php
/*
 * speedtest.widget.php - Dashboard widget for pfSense-pkg-speedtest
 *
 * Displays the most recent Speedtest CLI result on the pfSense dashboard.
 * Speedtest is a trademark of Ookla, LLC. Used with attribution.
 */

$widgetTitle = "Speed Test";

if (!file_exists('/usr/local/pkg/speedtest.inc')) {
	echo '<p class="text-muted" style="padding:8px;">Speed Test package not installed.</p>';
	return;
}

require_once('/usr/local/pkg/speedtest.inc');

$history    = speedtest_get_history();
$latest     = !empty($history) ? $history[0] : null;
$is_running = speedtest_is_running();
?>

<div id="speedtest-widget-inner">
<?php if ($is_running): ?>
	<div class="text-center text-muted" style="padding:14px 8px;">
		<i class="fa fa-circle-o-notch fa-spin" style="margin-right:6px;"></i>Test in progress&hellip;
	</div>
<?php elseif ($latest): ?>
	<div style="padding:6px 10px 2px;">

		<div class="row text-center" style="margin-bottom:8px;">
			<div class="col-xs-6" style="border-right:1px solid #eee;">
				<div style="font-size:10px;color:#999;text-transform:uppercase;letter-spacing:.6px;margin-bottom:2px;">Download</div>
				<div style="font-size:26px;font-weight:700;color:#337ab7;line-height:1.1;">
					<?= htmlspecialchars($latest['download_mbps']) ?>
				</div>
				<div style="font-size:11px;color:#777;">Mbps</div>
			</div>
			<div class="col-xs-6">
				<div style="font-size:10px;color:#999;text-transform:uppercase;letter-spacing:.6px;margin-bottom:2px;">Upload</div>
				<div style="font-size:26px;font-weight:700;color:#5cb85c;line-height:1.1;">
					<?= htmlspecialchars($latest['upload_mbps']) ?>
				</div>
				<div style="font-size:11px;color:#777;">Mbps</div>
			</div>
		</div>

		<div class="row text-center" style="border-top:1px solid #eee;padding-top:6px;margin-bottom:6px;">
			<div class="col-xs-6">
				<span style="font-size:11px;color:#999;">Ping</span>
				<span style="font-size:13px;font-weight:600;margin-left:4px;">
					<?= htmlspecialchars($latest['ping_ms']) ?>&thinsp;<span style="font-size:10px;color:#999;">ms</span>
				</span>
			</div>
			<div class="col-xs-6">
				<span style="font-size:11px;color:#999;">Jitter</span>
				<span style="font-size:13px;font-weight:600;margin-left:4px;">
					<?= htmlspecialchars($latest['jitter_ms']) ?>&thinsp;<span style="font-size:10px;color:#999;">ms</span>
				</span>
			</div>
		</div>

		<?php if (!empty($latest['isp']) || !empty($latest['server'])): ?>
		<div style="font-size:11px;color:#999;border-top:1px solid #eee;padding-top:5px;margin-bottom:4px;line-height:1.6;">
			<?php if (!empty($latest['isp'])): ?>
				<strong>ISP:</strong> <?= htmlspecialchars($latest['isp']) ?><br>
			<?php endif; ?>
			<?php if (!empty($latest['server'])): ?>
				<strong>Server:</strong> <?= htmlspecialchars($latest['server']) ?>
			<?php endif; ?>
		</div>
		<?php endif; ?>

		<div style="font-size:11px;color:#bbb;border-top:1px solid #eee;padding-top:4px;display:flex;justify-content:space-between;align-items:center;">
			<span><?= htmlspecialchars(date('M j, g:i a', strtotime($latest['timestamp']))) ?></span>
			<?php if (!empty($latest['result_url'])): ?>
				<a href="<?= htmlspecialchars($latest['result_url']) ?>" target="_blank" rel="noopener" style="font-size:11px;">View result</a>
			<?php endif; ?>
		</div>

	</div>
<?php else: ?>
	<div class="text-center text-muted" style="padding:16px 8px;">
		<p style="margin-bottom:8px;">No results yet.</p>
		<a href="/speedtest/speedtest.php" class="btn btn-xs btn-primary">Run a test</a>
	</div>
<?php endif; ?>

	<div style="text-align:right;padding:3px 10px 5px;">
		<a href="/speedtest/speedtest.php" style="font-size:11px;color:#bbb;">Speed Test &rsaquo;</a>
	</div>
</div>
