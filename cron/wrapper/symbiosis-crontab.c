/**
 * setuid crontab wrapper
 *
 * The way this script works is pretty simple:
 *
 *  1.  Iterate over every entry beneath /srv
 *      - Ignoring dotfiles.
 *      - Ignoring entries that do not contain /srv/$name/config/crontab
 *
 *  2.  Once a valid entry has been found ensure that the owner of
 *      /srv/$name and /srv/$name/config/crontab matches.
 *
 *  3.  Invoke our ruby wrapper as the appropriate user, via /bin/su.
 *
 * Steve
 * --
 */


#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>
#include <pwd.h>
#include <unistd.h>
#include <string.h>




/**
 * Global verbosity flag.
 */
int g_verbose = 0;




/**
 * fork() so that we can launch a program in the background.
 */
void fork_program( char *program )
{
  pid_t pid = fork();

  if ( pid == 0 )
  {
    system( program );
  }
  else if (pid < 0)
  {
    printf("Fork failed\n");
  }
}




/**
 * Process each entry beneath a given directory,
 * looking for crontabs and invoking our ruby wrapper upon each valid
 * one we find.
 */
int process_domains( const char *dirname )
{
   DIR *dp;
   struct dirent *dent;
   int i = 0;


   /**
    * Open the directory.
    */
   if((dp = opendir(dirname)) == NULL)
   {
       if ( g_verbose )
           printf("opendir(%s) - failed\n", dirname );
       return -1;
   }


   /**
    * Read each entry in the directory.
    */
   while((dent = readdir(dp)) != NULL)
   {
       struct stat domain;
       struct stat crontab;
       struct passwd *pwd;

       /**
        * Filename of crontab, if it exists.
        */
       char filename[ 1024 ] = { '\0' };


       /**
        * Command to run, if any.
        */
       char command[ 1024 ] = { '\0' };
       /**
        * Get the name.
        */
       const char *entry = dent->d_name;


       if ( g_verbose )
           printf("Read entry: %s\n", entry );

       /**
        * Skip dotfiles
        */
       if ( ( entry == NULL ) ||
            ( entry[0] == '.' ) )
       {
           if ( g_verbose )
               printf("\tIgnoring as dotfile.\n" );
           continue ;
       }


       /**
        * Look for /srv/$name/config/crontab
        */
       snprintf(filename, sizeof(filename)-1,
                "/srv/%s/config/crontab",
                entry );
       if ( stat( filename, &crontab ) != 0 )
       {
           if ( g_verbose )
               printf("\tIgnoring as /srv/%s/config/crontab doesnt exist\n",
                      entry );
           continue;
       }


       /**
        * OK we have /srv/$name & /srv/$name/config/crontab.
        *
        * Ensure the owners match.
        */
       snprintf(filename, sizeof(filename)-1,
                "/srv/%s", entry );
       if ( stat(filename, &domain ) != 0 )
       {
           if ( g_verbose )
               printf("\tstat( /srv/%s ) - failed\n", entry );
           continue;
       }


       /**
        * OK here we have two statbufs - one for /srv/$name, and
        * one for /srv/$name/config/crontab
        */
       if ( domain.st_uid != crontab.st_uid )
       {
           if ( g_verbose )
              printf("UIDs don't match for /srv/%s and /srv/%s/config/crontab\n", entry, entry );
           continue;
       }


       /**
        * Found a valid domain with a crontab - now we need to find
        * the username to execute with.
        *
        */
       pwd = getpwuid(domain.st_uid);
       if ( ( pwd == NULL ) ||
            ( pwd->pw_name == NULL ) )
       {
           if ( g_verbose )
           {
             printf("\tFailed to find username for UID %d\n", domain.st_uid );
             continue;
           }
       }


       /**
        * Build up the command to run, and execute it.
        */
       snprintf(command, sizeof(command)-1,
                "/bin/su -s /bin/sh -c '/usr/bin/symbiosis-crontab /srv/%s/config/crontab' %s)",
                entry, pwd->pw_name  );
       fork_program( command );
     }
   closedir(dp);
   return i;
}



/**
 * Entry point to our code.
 *
 * Accept only a single argument "--verbose"
 */
int main( int argc, char *argv[] )
{
    int i;

    for ( i = 1; i < argc; i++ )
    {
        if ( strcasecmp( argv[i], "--verbose" ) == 0 )
          g_verbose = 1;
    }

    process_domains( "/srv/" );
    return 0;
}
