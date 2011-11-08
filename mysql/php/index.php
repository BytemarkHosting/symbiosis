<?php

/**
 * This script is available at :
 *
 * http://localhost/_db/
 *
 * It is designed to test that a database login is present.
 *
 * For it to work it assumes that there is a login which can be
 * used for local MySQL access.  This login will be stored at
 *
 * /etc/mysql/symbiosis.cnf
 *
 * If that file doesn't exist then we do nothing.
 *
 */


/**
 * The location of the configuration file.
 */
$file = "/etc/mysql/symbiosis.cnf";


if ( file_exists( $file ) )
{

  /**
   * Parse the configuration file.
   */
  $config = parse_ini_file($file);

  if ( ! $config )
  {
    die( "The configuration file failed to parse - " . $file );
  }

  $user = $config["username"];
  $pass = $config["password"];

  if ( !$user )
  {
    die( "Configuration file failed to define a username " . $file );
  }
  if ( !$pass )
  {
    die( "Configuration file failed to define a password " . $file );
  }

  /**
   * The configuration file exists - we can proceed.
   */
  $link = mysql_connect('localhost', $user, $pass );

  if (!$link)
  {
    die('Could not connect: ' . mysql_error());
  }

  mysql_close($link);

  /**
   * We connected, and disconnected successfully.
   */
  echo 'OK';
}
else
{

  /**
   * The configuration file was missing.
   */
  echo ( "Missing configuration file: " . $file  );

}
?>
