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
if ( !is_array($config) ) {
  $config = array();

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

if ( !array_key_exists('login_lc', $config) ) {
  /*
   * Forces conversion of logins to lower case.
   */ 
  $config['login_lc'] = 2;
}


if ( !array_key_exists('log_driver', $config) ) {
  /*
   * Log to syslog
   */
  $config['log_driver'] = 'syslog';

  /*
   * Log failed logins
   */
  $config['log_logins'] = true;

  /*
   * Log session authentication errors
   */
  $config['log_session'] = true;

}


/*
 * Enable the password changing plugin, if it has not already been enabled.
 */
if ( array_search("password", $config['plugins']) === false ) {
  $config['plugins'][] = "password";

  /*
   * We use poppassd in Symbiosis
   */
  $config['password_driver'] = 'poppassd';

  /*
   * The user has to confirm their current password
   */
  $config['password_confirm_current'] = true;

  /*
   * The host which changes the password
   */
  $config['password_pop_host'] = 'localhost';

  /*
   *  TCP port used for poppassd connections
   */
  $config['password_pop_port'] = 106;
}


