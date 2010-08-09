/**
 *
 * Test the password(s) specified upon the command line for weakness.
 *
 */



#include <crack.h>
#include <stdio.h>
#include <string.h>


/*
 * Ensure we have a path setup - these seems to have changed
 * since Etch.
 */
#ifndef CRACKLIB_DICTPATH
#   define CRACKLIB_DICTPATH "/var/cache/cracklib/cracklib_dict"
#endif



/**
 * Test the password stored in the file given upon command line.
 */
int main( int argc, char *argv[] )
{
    char const* msg;
    char line[1024];
    FILE *f;
    int i;
    int fail = 0;

    for ( i = 1; i < argc; i++ )
    {
        f = fopen( argv[i], "r" );
        memset(line, '\0',sizeof(line));

        if ( f == NULL )
        {
            fprintf(stderr, "Failed to open file: %s\n", argv[i] );
        }
        else
        {
            int j = 0;

            /**
             * Read password.
             */
            fgets( line, sizeof(line)-1, f );

            /**
             * Strip newline(s).
             */
            while( line[j] != '\0' )
            {
                if ( ( line[j] == '\r' ) || ( line[j] == '\n' ) )
                    line[j] = '\0';

                j+=1;
            }
            fclose( f );


            /**
             * Test password.
             */
            if ( strlen( line ) > 0 )
            {
                msg = FascistCheck( line, CRACKLIB_DICTPATH );

                if( msg )
                {
                    printf( "Password '%s' stored in '%s' is insecure:\n\t%s\n",
                            line, argv[i], msg );
                    fail = 1;
                }
            }
            else
            {
              fprintf(stderr, "Skipping empty file: %s\n", argv[i] );
            }
        }
    }
    return fail;
}

#if 0


=head1 NAME

passwd-test - Test a given password for strength

=head1 SYNOPSIS

  passwd-test file1 file2 ... fileN

=cut

=head1 DESCRIPTION

The B<passwd-test> binary is designed to test the passwords
contained within the file(s) specified upon  the command line
for strenth.

Passwords will be tested using the cracklib testing library,
and any weak passwords will be reported to the console.

=cut

=head1 SEE-ALSO

See the manpage for B<test-symbiosis-passwords> for details
of when and how this tool is invoked.

=cut

#endif
