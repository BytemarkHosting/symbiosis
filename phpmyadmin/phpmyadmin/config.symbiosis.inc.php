<?php
/**************************************************
 * PhpMyAdmin configuration options for Symbiosis *
 **************************************************/

/*
 * This flag mandates the use of SSL, causing http requests to be redirected to
 * https.
 */
$cfg['ForceSSL'] = true;

/*
 * This iterates through each of the servers configured, at makes aure that the
 * auth is done over HTTP, and that debian-sys-maint is denied from logging in.
 */
foreach (array_keys($cfg['Servers']) as $svr) {
  /*
   * This setting uses HTTP BasicAuth rather than cookies for authentication,
   * this is more sane in the presence of remote attackers probing your server.
   */
  $cfg['Servers'][$svr]['auth_type'] = 'http';

  /*
   * This snippet denies logins to the 'debian-sys-maint' user, which is
   * provided by the Debian mysql-server package(s).
   */
  $cfg['Servers'][$svr]['AllowDeny']['order'] = 'deny,allow';
  $cfg['Servers'][$svr]['AllowDeny']['rules'] = array( 'deny debian-sys-maint from all' );
}


