#!/usr/bin/perl -w -I./perl-lib/
#
#  Test that plaintext logins work.
#

use Test::More qw( no_plan );

#
#  Utility functions for creating a new domain.
#
require 'tests/00-common.inc';


#
#  Create a domain 10 times
#
my $count = 0;

while ( $count < 10 )
{

    #
    #  Get a Symbiosis::Domain object.
    #
    my $helper = createDomain();

    #
    #  A new domain will have a name.
    #
    ok( $helper->name(), " A new domain has a name" );

    #
    #  By default a new domain won't have a password
    #
    ok( !$helper->isFTP(), " A new domain doesn't have a password setup" );

    #
    #  The domain exists
    #
    ok( $helper->exists(), " The domain exists [1/2]" );
    ok( -d $helper->path() ,  " The domain exists [2/2]" );


    #
    #  Setup a random plaintext password
    #
    my $path = $helper->path();
    my $pass = writePlainPassword("$path/config/ftp-password");

    #
    #  OK now we should find there is an FTP password.
    #
    ok( $helper->isFTP(), " After setting a password it is FTP-aware" );

    #
    #  Finally does the login work?
    #
    ok( $helper->loginFTP($pass), " The password works" );

    #
    #  All done for this round.
    #
    $count += 1;
}
