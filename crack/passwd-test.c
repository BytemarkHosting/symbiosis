/**
 *
 * Test the password(s) specified upon the command line for weakness.
 *
 */



#include <crack.h>
#include <stdio.h>


/*
 * Ensure we have a path setup - these seems to have changed
 * since Etch.
 */
#ifndef CRACKLIB_DICTPATH
#   define CRACKLIB_DICTPATH "/var/cache/cracklib/cracklib_dict"
#endif



/**
 * Test the password specified upon the command line.
 */
int main( int argc, char *argv[] )
{
    char const* msg;
    int i;
    int fail = 0;

    for ( i = 1; i < argc; i++ )
    {
        msg = FascistCheck( argv[i], CRACKLIB_DICTPATH );

        if( msg )
        {
            printf( "Password '%s' is insecure:\n\t%s\n",
                    argv[i], msg );
            fail = 1;
        }
    }
    return fail;
}

#if 0


=head1 NAME

passwd-test - Test a given password for strength

=head1 SYNOPSIS

  passwd-test password1 password2 ... passwordN

=cut

=head1 DESCRIPTION

The B<passwd-test> binary is designed to test the password(s)
specified upon the command line for strenth.

Passwords will be tested using the cracklib testing library,
and any weak passwords will be reported to the console.

=cut

=head1 SEE-ALSO

See the manpage for B<test-symbiosis-passwords> for details
of when and how this tool is invoked.

=cut

#endif
