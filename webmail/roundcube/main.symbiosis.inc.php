<?php
/*****************************************************************************
 *
 * This configuration is deployed with Bytemark Symbiosis.  Feel free to make
 * changes here, or to the original configuration in
 * /etc/roundcube/main.inc.php.dpkg-symbiosis-orig.
 *
 ****************************************************************************/


/**
 * Read in original, main config.
 */
if (is_readable('/etc/roundcube/main.inc.php.dpkg-symbiosis-orig')) {
  include_once('/etc/roundcube/main.inc.php.dpkg-symbiosis-orig');
}

/**
 * Set the default server host, if not already set.
 */
if ( !array_key_exists('default_host', $rcmail_config) or
     strlen($rcmail_config['default_host']) == 0 ) {

  $rcmail_config['default_host'] = 'localhost';

}

/**
 * Make sure the plugins array exists.
 */
if ( !array_key_exists('plugins', $rcmail_config) ) {

  $rcmail_config['plugins'] = array();

}

/**
 * Now check to ensure the managesieve plugin is enabled.
 */
if ( array_search("managesieve", $rcmail_config['plugins']) === false ) {
  $rcmail_config['plugins'][] = "managesieve";

  /**
   * Set the default port to 4190.
   */
  $rcmail_config['managesieve_port'] = 4190;

  /**
   * Make sure mailbox names are encoded in UTF-8 for dovecot (see
   * http://wiki2.dovecot.org/Pigeonhole/Sieve/Troubleshooting)
   */
  $rcmail_config['managesieve_mbox_encoding'] = 'UTF-8';
}
