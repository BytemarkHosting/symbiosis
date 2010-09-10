/**
 * This single header-file is the source of the string-manipulation
 * which is performed by the mod_vhost_bytemark module.
 *
 * The intention is that this code will map between a hostname
 * and a directory.
 *
 * Request for www.example.com -> /srv/example.com/public/htdocs
 * Request for example.com     -> /srv/example.com/public/htdocs
 *
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
   * OK at this point we've found /srv/xxxxx.
   *
   * Copy from the /srv marker to the period.
   */
  memcpy( path + strlen( "/srv/" ), per + 1,
         strlen( per+1) );
}



#endif /* _MOD_VHOST_BYTEMARK_H */
