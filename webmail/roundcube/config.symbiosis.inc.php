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
if ! is_array( $config ) {
  $confg = array();
}

/**
 * Set the default server host, if not already set.
 */
if ( !array_key_exists('default_host', $config) or
     strlen($config['default_host']) == 0 ) {

  $config['default_host'] = 'localhost';

}

/**
 * Make sure the plugins array exists.
 */
if ( !array_key_exists('plugins', $config) ) {
  $config['plugins'] = array();
}

/**
 * Now check to ensure the managesieve plugin is enabled.
 */
if ( array_search("managesieve", $config['plugins']) === false ) {
  $config['plugins'][] = "managesieve";

  /**
   * Set the default port to 4190.
   */
  $config['managesieve_port'] = 4190;

  /**
   * Make sure mailbox names are encoded in UTF-8 for dovecot (see
   * http://wiki2.dovecot.org/Pigeonhole/Sieve/Troubleshooting)
   */
  $config['managesieve_mbox_encoding'] = 'UTF-8';

  /* Enables separate management interface for vacation responses (out-of-office)
   * 0 - no separate section (default),
   * 1 - add Vacation section,
   * 2 - add Vacation section, but hide Filters section
   */
  $config['managesieve_vacation'] = 1;

}

if ( !array_key_exists('force_https', $config) ) {
  /*
   * Make sure all connections are secure. 
   */
  $config['force_https'] = true;
}

