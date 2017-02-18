<?php
function hex2bin($data)
{
	$data = ltrim($data, "\x");
	$len = strlen($data);
	return pack("H" . $len, $data);
} 

$dbconn = pg_connect("dbname=contrib_regression port=65432 user=postgres");
$rs = pg_query( $dbconn, "select plr_get_raw(filt_r_ps(data)) from test_ts_obj where dataid = 42");
$hexpic = pg_fetch_array($rs);
$cleandata = hex2bin($hexpic[0]);

header("Content-Type: image/jpeg");
header("Last-Modified: " .
date("r", filectime($_SERVER['SCRIPT_FILENAME'])));
header("Content-Length: " . strlen($cleandata));
echo $cleandata;
?>
