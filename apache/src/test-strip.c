#include <string.h>
#include <stdlib.h>
#include <stdio.h>


/**
 * Strip the "www." part from a name, after "/srv".
 *
 */
void convert( char *filename )
{
  char prefix[] = "/srv";

  /* find www */
  char *p = strstr( filename, "www." );

  printf( "convert: %s\n", filename );

  if ( ( p != NULL ) &&
       ( p == filename + strlen(prefix) + 1 ) )
    {
      /* strlen( "www." ) == 4  */
      memcpy( p ,  p +4, strlen(p) - 4 + 1) ;
  }


  printf( "result: %s\n", filename );

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
                       "/srv/foo.com/public/htdocs/index.html",
                       "/srv/bar.com/public/htdocs/stats/index.html",
                       "/srv/bar.com/public/cgi-bin/test.cgi",
                       "/srv/foo.com/srv/www.com/public/htdocs",
                       "/srv/www.steve.org.uk/public/blah",
                       "/srv/WWW.steve.org.uk/public/blah",
                       "/srv/www.steve.org.uk/public/blah",
                       "/srv/electronicnews.co.uk/cgi-bin/formail.cgi",
                       "/srv/www/electronicnews.co.uk/cgi-bin/formail.cgi",
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


