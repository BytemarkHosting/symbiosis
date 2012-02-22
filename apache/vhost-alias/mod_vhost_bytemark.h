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
 * In short if a request for a file doesn't exist we'll remove sections of
 * the requested hostname until we find a directory which exists.
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
 * Copyright (c) 2008-2012 Bytemark Computer Consulting Ltd.
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
 * We'll be passed a path to a request, on disk, which doesn't exist
 * such as: /srv/www.example.com/public/htdocs
 *
 * We want toremove components of that name until we find something
 * that does exist, if we can.
 *
 * If we cannot find something which exists, by removing components
 * from the hostname field, then we'll simply return the string
 * unmodified - which will allow Apache to handle it as-is.
 *
 *
 * NOTE: We can always successfully remove string-components in-place
 *      as this always *reduces* the string in length.
 *
 */
void update_vhost_request( char *path )
{
  char *srv = NULL;
  char *per = NULL;
  struct stat statbuf;
  int i;
  int host;


  /**
   * Ensure we received an input.
   */
  if ( NULL == path )
    return ;


  /**
   * Find /srv as a sanity check - it should be first part of the string.
   */
  srv = strstr(path,"/srv/");
  if ( ( NULL == srv ) || ( srv != path ) )
    return;


  /**
   * If the request exists we're golden.
   *
   * NOTE: We shouldn't be called in this case, but it doesn't hurt to try.
   */
  if ( stat( path, &statbuf ) == 0 )
    return;


  /**
   * Log the missing request.
   */
#if 0
  fprintf(stderr,"mod_vhost_bytemark.c: path not found %s\n", path);
#endif

  /**
   * OK at this point we have a request which points to a file
   * which doesn't exist.
   *
   * So we might have:
   *
   *   /srv/www.example.com/public/htdocs/index.php
   *
   * We take the first component of that string "www.example.com"
   * and will remove successive parts over time.
   *
   * If _any_ of those result in a stat() succeeding we update
   * and return.
   *
   * If they do not we will assume mod_rewrite, mod_userdir, mod_alias,
   * or "something else" will patch up - otherwise we'll end up with
   * a 404.
   *
   */


  /**
   * OK we want to find the string after /srv/
   * but before the first slash
   */
  per = strstr( path + strlen("/srv/" ), "/" );
  if ( per == NULL )
    return;


  /**
   * We want to bump-past the slash.
   */
  per +=1;


  /**
   * The length of the hostname in the request.
   */
  host = per - srv - strlen("/srv/");
  if ( host > 128 )
  {
#if 0
    fprintf(stderr,"mod_vhost_bytemark.c: hostname too long: %d bytes\n",host);
#endif
    return;
  }



  /**
   * Try increasingly stat()ing over parts of the hostname
   * until we find a match.
   */
  for ( i = 1; i < host; i++ )
  {
    char buffer[1024];

    /**
     * Build up each part of the name.
     */
    memset(buffer, '\0', sizeof(buffer));
    strcpy(buffer,"/srv/" );
    strncpy( buffer+5,srv+4 + i, host - i );


    /**
     * If we can successfully state "/srv/" + $hostname
     * then we'll update the string with that name.
     */
    if ( stat( buffer, &statbuf) == 0 )
    {
      memcpy( path+5, srv+4+i, strlen(srv+4+i)+1 );
#if 0
      fprintf(stderr,"mod_vhost_bytemark.c: succeeded on %s -> %s\n",buffer, path);
#endif
      return;
    }
  }

  /**
   * Failure -> 404.
   */
#if 0
  fprintf(stderr,"mod_vhost_bytemark.c: giving up\n" );
#endif
}



#endif /* _MOD_VHOST_BYTEMARK_H */
