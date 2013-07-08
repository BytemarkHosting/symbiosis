/**
 *
 * A wrapper script which will do some simple permission and file-presence
 * checks, then launch the symbiosis-crontab command for each domain which
 * is present.
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

#define CRONTAB_HELPER "/usr/bin/symbiosis-crontab"
#define SRV_DIR        "/srv"

/**
 * fork() so that we can launch a program in the background.
 */
void process_crontab( char *crontab_path, char *domain_path, struct passwd *pwd )
{
    pid_t pid;
          
    if ( (pid = fork()) == 0 )
    {
        if( g_verbose )
           printf("Processing: %s as UID %i:%i\n", crontab_path, pwd->pw_uid, pwd->pw_gid );

        /**
         *  Change UID 
         */
        if( setgid(pwd->pw_gid) == 0 && setuid(pwd->pw_uid) == 0 ) {
          /*
           *  Live in /srv/domain.com by default 
           */
          chdir(domain_path);

          /**
           * Fix up environment (this was cleared some time ago)
           */
          setenv("HOME", pwd->pw_dir, 1);
          setenv("SHELL", pwd->pw_shell, 1);
          setenv("LOGNAME", pwd->pw_name, 1);
          setenv("PATH", "/usr/bin:/bin", 1);

          /**
           * Run the helper
           */
          char *args[] = { CRONTAB_HELPER, crontab_path, (char *) 0 };

          execv(*args, args);
          printf("*** ERROR: exec failed\n");
          exit( 1 );
        }
        else
        {
          printf("*** ERROR: Unable to change UID.");
          exit( 1 );
        }
    }
    else if (pid < 0)
    {
        printf("*** ERROR: Fork failed\n");
        exit( 1 );
    }
}



/**
 * Process each entry beneath a given directory,
 * looking for crontabs and invoking our ruby wrapper upon each valid
 * one we find.
 */
void process_domains( const char *dirname )
{
   DIR *dp;
   struct dirent *dent;

   /**
    * Open the directory.
    */
   if((dp = opendir(dirname)) == NULL)
   {
       if ( g_verbose )
           printf("opendir(%s) - failed\n", dirname );
       return;
   }

   /**
    * Read each entry in the directory.
    */
   while((dent = readdir(dp)) != NULL)
   {
       struct stat domain;
       struct stat crontab;

       /**
        * Path of domain & crontab, if it exists.
        */
       char domain_path[ 1024 ] = { '\0' };
       char crontab_path[ 1024 ] = { '\0' };

       /**
        * Get the name of this entry beneath /srv
        */
       const char *entry = dent->d_name;
       
       /**
        * Data from /etc/password for the user
        */
       struct passwd *pwd;

       if ( g_verbose )
           printf("Read entry: %s\n", entry );


       /**
        * Skip any dotfiles we might have found.
        */
       if ( ( entry == NULL ) ||
            ( entry[0] == '.' ) )
       {
           if ( g_verbose )
               printf("\tIgnoring as dotfile.\n" );
           continue ;
       }

       /**
        * Stat /srv/domain to make sure it is a directory
        *
        */
       snprintf(domain_path, sizeof(domain_path)-1,
                "%s/%s", dirname, entry );
       if ( stat(domain_path, &domain ) != 0 )
       {
           if ( g_verbose )
               printf("\tstat( %s ) - failed\n", domain_path );
           continue;
       }
      
      /**
       *  Make sure the domain directory is a directory 
       */

      if ( ! S_ISDIR(domain.st_mode) )
       {
           if ( g_verbose )
               printf("\tIgnoring as %s is not a directory\n", domain_path);

           continue;
       }
       
        /**
        * Look for /srv/$name/config/crontab, and make sure it is a file.
        *
        */
       snprintf(crontab_path, sizeof(crontab_path)-1,
                "%s/%s/config/crontab",
                dirname, entry );

       if ( stat( crontab_path, &crontab ) != 0 )
       {
           if ( g_verbose )
               printf("\tIgnoring as %s doesnt exist\n", crontab_path );

           continue;
       }

       if ( ! S_ISREG(crontab.st_mode) )
       {
           if ( g_verbose )
               printf("\tIgnoring as %s is not a file\n", crontab_path);

           continue;
       }


      /**
       * Lookup the userid in /etc/password
       */
      pwd = getpwuid(domain.st_uid);
      if ( ( pwd == NULL ) ||
           ( pwd->pw_name == NULL ) )
      {
          if ( g_verbose )
              printf("\tFailed to find username for UID %d\n", domain.st_uid );
          continue;
      }
      
      /**
       * make sure that the user has a sane UID
       */
      if ( pwd->pw_uid < 1000 || pwd->pw_gid < 1000)
      {
          if ( g_verbose )
              printf("Owner UID/GID is less than 1000 for %s owned by %s -- not processing.\n", domain_path, pwd->pw_name );
           continue;
      }

 
      /*
       * finally process the crontab
       */
      process_crontab( crontab_path, domain_path, pwd );
   }

   closedir(dp);
}



/**
 * Entry point to our code.
 *
 * Accept only a single argument "--verbose"
 */
int main( int argc, char *argv[] )
{
    int i;
    struct stat statbuf;

    /**
     * Empty our enviroment
     */
    clearenv();

    /**
     * Make sure we're root
     */
    if( getuid() != 0 ) 
    {
      printf("This program must be invoked as root.\n");
      return -1;
    }

    /**
     * Parse arguments looking for a verbose flag.
     */
    for ( i = 1; i < argc; i++ )
    {
        if ( strcasecmp( argv[i], "--verbose" ) == 0 )
          g_verbose = 1;
    }

    /**
     * See if we have our helper present.
     */
    if ( stat( CRONTAB_HELPER, &statbuf ) != 0 )
    {
        if ( g_verbose )
            printf("Our helper is missing: %s\n", CRONTAB_HELPER );

        return -1;
    }


    /**
     * Ensure that /srv is present.
     */
    if ( stat( SRV_DIR, &statbuf ) != 0 )
    {
        if ( g_verbose )
            printf( "%s isn't present.\n", SRV_DIR );

        return -1;
    }

    /**
     * Ensure /srv is a directory.
     */
    if ( ! S_ISDIR( statbuf.st_mode ) )
    {
        if ( g_verbose )
            printf( "%s isn't a directory.\n", SRV_DIR );

        return -1;
    }


    /**
     * OK we're good to proceed.
     */
    process_domains( SRV_DIR );


    /**
     * All done.
     */
    return 0;
}
