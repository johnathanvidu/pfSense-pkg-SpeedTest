<?php
/*
 * speedtest.priv.inc - Privilege definitions for pfSense-pkg-speedtest
 *
 * Auto-discovered by pfSense from /etc/inc/priv/ at startup.
 */

global $priv_list;

$priv_list['page-services-speedtest'] = [
	'name'  => 'WebCFG - Services: Speed Test',
	'descr' => 'Allow access to the Services: Speed Test package page.',
	'match' => [
		'speedtest/speedtest.php*',
	],
];
