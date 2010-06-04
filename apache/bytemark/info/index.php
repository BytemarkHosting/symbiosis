<html>
 <head>
   <title> <?php  system( "hostname" ) ?></title>
   <meta http-equiv="Content-Type" content="text/html;charset=UTF-8">
 </head>
 <body>

<h1>System Information</h1>
<blockquote>
<p>Some system information:</p>
<table padding="5" cellspacing="5" border="1">
<tr><td>Hostname</td><td> <?php  system( "hostname" ) ?></td></tr>
<tr><td valign="top">Networking details</td><td><pre><?php system( "/sbin/ifconfig | grep -A1 eth" ); ?></pre></td>
<tr><td valign="top">Disk Space</td><td><pre><?php system( "df --si /"); ?></pre></td></tr>
<tr><td valign="top">Debian Version</td><td><pre><?php system( "cat /etc/issue") ; ?></pre></td></tr>
<tr><td valign="top">Kernel Version</td><td><pre><?php system( "uname -r") ; ?></pre></td></tr>
</table>
</blockquote>

<h1>Vhost Information</h1>
<blockquote>
<p>The following virtual domains are hosted upon this machine:</p>
<blockquote>
<ul>
<?php
$dir = opendir("/srv");
while (($file = readdir($dir)) !== false)
{
  if (($file != '.')&&($file != '..') && (is_dir("/srv/".$file) ))
  {
     echo "<li><a href=\"http://$file\">$file</a></li>\n";
  }
}
closedir($dir);
 ?>
</ul>
</blockquote>
</blockquote>

<h1>Package Information</h1>
<blockquote>
<p>The following vhost packages are installed:</p>
  <table>
  <tr><th>Package</th><th>Version</th></tr>
 <?php
   $packages=`dpkg --list | grep ^ii | awk '{print $2}' | egrep '(bytemark|symbiosis)' |sort -u`;
   $array = preg_split( "/\s/", $packages, -1, PREG_SPLIT_NO_EMPTY );
   foreach ( $array as $package ) {
	$version = `dpkg-query -W -f='\${Version}' $package 2>/dev/null`;
	echo "<tr><td>$package</td><td>$version</td></tr>";
   }
  ?>
  </table>
 </blockquote>

 </body>
</html>
