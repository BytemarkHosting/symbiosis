#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include "mod_vhost_bytemark.h"


/**
 * Strip the "www." part from a name, after "/srv".
 *
 */
void convert( char *filename )
{

  printf( "convert: %s\n", filename );
  update_vhost_request( filename );
  printf( "result: %s\n\n", filename );

}

/**
 * Simple driver code.
 */
int main( int argc, char *argv[] )
{
  /*
   * Test strings.
   */
  char *filename[] = { "/srv/www.foo.com/public/htdocs/index.html",
                       "/srv/www.steve.org.uk/public/blah",
                       "/srv/WWW.steve.org.uk/public/blah",
                       "/srv/pies.steve.org.uk/public/blah",
                       "/srv/WWW.steve.org.uk/public/blah",
                       "/srv/static.steve.org.uk/public/blah",
                       "/srv/electronicnews.co.uk/cgi-bin/formail.cgi",
                       "/srv/www.electronicnews.co.uk/cgi-bin/formail.cgi",
                       "/srv/cake.electronicnews.co.uk/cgi-bin/formail.cgi",
  };

  int i = 0;

  int count = sizeof( filename ) / sizeof(filename[0]);
  for(  i = 0; i < count ; i++ )
    {
      char *copy = strdup( filename[i] );
      convert( copy );
      free( copy );
    }

  return 0;
}


