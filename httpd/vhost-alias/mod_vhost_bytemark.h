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


#ifndef _SRV_
# define _SRV_ "/srv/"
#endif


/**
 * This is where the magic happens.
 *
 * We'll be passed a path to a request, on disk, which doesn't exist
 * such as: /srv/www.example.com/public/htdocs
 *
 * We want to remove components of that name until we find something
 * that does exist, if we can.
 *
 * If we cannot find something which exists, by removing components
 * from the hostname field, then we'll simply return the string
 * unmodified - which will allow Apache to handle it as-is.
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


  /**
   * Ensure we received an input.
   */
  if ( NULL == path )
    return ;


  /**
   * Find /srv as a sanity check - it should be first part of the string.
   */
  srv = strstr(path, _SRV_);
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
#if VHOST_DEBUG
  fprintf(stderr,"mod_vhost_bytemark.c: path not found %s\n", path);
#endif


  /**
   * OK at this point we have a request which points to a file which
   * doesn't exist.
   *
   * So we might have:
   *
   *   /srv/www.example.com/public/htdocs/index.php
   *
   * This string is made up of three parts;
   *
   *  - The static prefix: "/srv/".
   *
   *  - The hostname: "www.example.com".
   *
   *  - The requested resource: "/public/htdocs/index.php".
   *
   * We don't know if the file exists, but we can test if the hostname
   * is hosted locally by looking for /srv/$hostname.
   *
   * We will stat the hostname, looking at each sub-string, because
   * we want to look for common suffixes.  For example:
   *
   *   www.example.com -> example.com
   *
   *   sub.dom.example.com -> example.com
   *
   * This means we're looking for the right-most match and that can be
   * discovered by iterating over the length of the hostname and trying
   * each one.
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
   * OK we want to find the hostname.
   *
   * The hostnaem is the string after /srv/, but before the first slash.
   */
  per = strstr( path + strlen( _SRV_ ), "/" );
  if ( per == NULL )
    return;


  /**
   * At this point we can calculate the host-length.
   */
  int host_len = per - path - 5  /* strlen("/srv/" ); */ ;
  if ( host_len >= 128 )
  {
    fprintf(stderr,"mod_vhost_bytemark.c: hostname too long: %d bytes\n", host_len);
    return;
  }


  /**
   * So now we have a hostname - save it away in the host_name buffer.
   */
  char host_name[256];
  memset( host_name, '\0', sizeof(host_name)-1);
  strncpy( host_name,
           path + strlen(_SRV_),
           per - path - 5  /* strlen("/srv/" ); */  );


  //#define VHOST_DEBUG 1
#ifdef VHOST_DEBUG
  printf( "XXX: Incoming Request was: %s\n", path );
  printf( "     Hostname - %s [%d]\n", host_name, host_len );
  printf( "     Path  - %s\n", per );
#endif


  /**
   * So now we have:
   *
   *  1.  The hostname stored in "host_name"  (www.foo.com)
   *  2.  The hostname length stored in "host_len" (11)
   *  3.  The requested path stored in "per" ("/index.php").
   *
   * Take a copy of the path that is requested.
   */
  char *path_copy = strdup( per );
  int path_len = strlen( per );



  /**
   * Try increasingly stat()ing over parts of the hostname
   * until we find a match.
   */
  for ( i = 0; i < host_len - 1; i++ )
  {

     /**
      * We know the hostname cannot be more than 128 bytes, so we're
      * safe to declare this as 256.
      */
     char buffer[256];

     /**
      * Add the /srv/ + domain-piece prefix.
      */
     memset(buffer, '\0', sizeof(buffer));
     strcpy(buffer, _SRV_ );
     strncpy(buffer + 5, host_name + i, host_len - i );


     /**
      * If we can successfully state "/srv/" + $hostname
      * then we'll update the string with that name.
      */
     if ( stat( buffer, &statbuf) == 0 )
     {
        memmove( path+5, srv+4+i, strlen(srv+5+i) );

#ifdef VHOST_DEBUG
        fprintf(stderr,"mod_vhost_bytemark.c: succeeded on %s -> %s\n",buffer, path);
#endif

        /**
         * Zero the RAM we were given.
         */
        memset(path, '\0', path_len );

        /**
         * Add the hostname we statted.
         */
        strcpy( path, buffer );

        /**
         * Add the request - which will start with "/".
         */
        strcat(path, path_copy );

        /**
         * Free the copy of the requested-path we took.
         */
        free(path_copy);
        return;
    }

#ifdef VHOST_DEBUG
     fprintf(stderr, "failed to stat: %s\n", buffer );
#endif
}

  /**
   * Failure -> 404.
   */
#ifdef VHOST_DEBUG
  fprintf(stderr,"mod_vhost_bytemark.c: giving up\n" );
#endif

  free(path_copy);
}



#endif /* _MOD_VHOST_BYTEMARK_H */
