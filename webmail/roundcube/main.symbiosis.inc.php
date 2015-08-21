<?php
/*****************************************************************************
 *
 * This configuration is deployed with Bytemark Symbiosis.  Feel free to make
 * changes here.
 *
 ****************************************************************************/

/*
 * Make sure the configuration array is defined.
 */
if ! is_array( $rcmail_config ) {
  $rcmail_config = array();
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

  /* Enables separate management interface for vacation responses (out-of-office)
   * 0 - no separate section (default),
   * 1 - add Vacation section,
   * 2 - add Vacation section, but hide Filters section
   */
  $rcmail_config['managesieve_vacation'] = 1;

}

if ( !array_key_exists('force_https', $rcmail_config) ) {
  /*
   * Make sure all connections are secure. 
   */
  $rcmail_config['force_https'] = true;
}

