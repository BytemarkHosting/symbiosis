/**
 * This single header-file is the source of the string-manipulation
 * which is performed by the mod_vhost_bytemark module.
 *
 * The intention is that this code will map between a hostname
 * and a directory.
 *
 * Request for www.example.com  -> /srv/example.com/public/htdocs
 * Request for test.example.com -> /srv/example.com/public/htdocs
 * Request for example.com      -> /srv/example.com/public/htdocs
 *
 * In short we drop the first period-deliminated section of the
 * filename, after /srv/, and hope for the best.
 *
 * This code is only invoked in a situation where a 404 would have
 * resulted anyway so if it fails it fails.
 *
 * Steve
 * --
 *
 */


/*
 * mod_vhost_bytemark.h: support for dynamically configured mass virtual
 * hosting for Bytemark Symbiosis.
 *
 * This software is based upon mod_vhost_alias.c, which was released under the
 * Apache licence, version 2.0.
 *
 * Copyright (c) 2008-2010 Bytemark Computer Consulting Ltd.
 * Copyright (c) 1998-1999 Demon Internet Ltd.
 *
 * mod_vhost_alias.c was submitted by Demon Internet to the Apache Software Foundation
 * in May 1999. Future revisions and derivatives of this source code
 * must acknowledge Demon Internet as the original contributor of
 * this module. All other licensing and usage conditions are those
 * of the Apache Software Foundation.
 *
 * Originally written by Tony Finch <fanf@demon.net> <dot@dotat.at>.
 *
 * Implementation ideas were taken from mod_alias.c. The overall
 * concept is derived from the OVERRIDE_DOC_ROOT/OVERRIDE_CGIDIR
 * patch to Apache 1.3b3 and a similar feature in Demon's thttpd,
 * both written by James Grinter <jrg@blodwen.demon.co.uk>.
 */



#ifndef _MOD_VHOST_BYTEMARK_H
#define _MOD_VHOST_BYTEMARK_H 1


#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>


/**
 * This is where the magic happens.
 *
 * Given a name like /srv/boo.example.com/public/htdocs
 *
 * Remove "boo." from the name.  In place.
 *
 * NOTE: We can remove things in-place as the string is *always*
 *       reduced in length.
 *
 */
void update_vhost_request( char *path )
{
  char *srv = NULL;
  char *per = NULL;

  /**
   * Find /srv as a sanity check
   */
  srv = strstr(path,"/srv/" );
  if ( NULL == srv )
    return;

  /**
   * OK we want to find the string after /srv/
   * but before the first period.
   */
  per = strstr( path + strlen("/srv/" ), "." );
  if ( per == NULL )
    return;

  /**
   * We want to ensure there is content after the 
   * period.
   */
  if ( per[1] == '\0' )
    return;


  /**
   * OK at this point we've found /srv/xxxxx.
   *
   * Copy from the /srv marker to the period.
   */
  memcpy( path + strlen( "/srv/" ), per + 1,
         strlen( per+1 ) + 1 );
}



#endif /* _MOD_VHOST_BYTEMARK_H */
