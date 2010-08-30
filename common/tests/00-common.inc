#!/usr/bin/perl -w -I./perl-lib/
#
#  A utility method which will create a random domain and password.
#
#
#


use Test::More;
use Digest::MD5;
use File::Temp qw/ tempdir /;
use File::Path;


#
#  Load the modules we use.
#
BEGIN {use_ok('Symbiosis::Domains');}
require_ok('Symbiosis::Domains');
BEGIN {use_ok('Symbiosis::Domain');}
require_ok('Symbiosis::Domain');



#
#  Create a new temporary domain, and return the object holding
# that
#
sub createDomain
{

    #
    #  Pick a random domain name.
    #
    my $domain = join( '', map {( 'a' .. 'z' )[rand 26]} 0 .. 7 );

    #
    #  pick a random suffix.
    #
    my @tlds = qw/ .com .org .net .co.uk /;
    my $tld  = $tlds[rand @tlds];

    #
    #  The complete thing.
    #
    $domain = $domain . $tld;


    #
    #  Make a temporary directory
    #
    my $dir = tempdir( CLEANUP => 1 );


    #
    #  Create the domain
    #
    mkpath( $dir . "/$domain/config", { verbose => 0 } );

    #
    #  Create the helper
    #
    my $helper = Symbiosis::Domain->new( path => $dir . "/$domain" );


    #
    # Is the object the correct type?
    #
    isa_ok( $helper, "Symbiosis::Domain" );

    return ($helper);
}


=begin doc

Write a random MD5 password to the file specified,
and return the plaintext that will be corresponding to it.

=end doc

=cut

sub writeMD5Password
{
    my ($file) = (@_);

    #
    #  Pick a random passsword
    #
    my $pass = join( '', map {( 'a' .. 'z' )[rand 26]} 0 .. 12 );

    #
    #  Now write out that in an MD5 sense.
    #
    my $ctx = Digest::MD5->new();
    $ctx->add($pass);

    open( FILE, ">", $file ) or
      die "Failed to write to $file - $!";
    print FILE $ctx->hexdigest() . "\n";
    close(FILE);

    return ($pass);
}


=begin doc

Write a random password to the file specified,
and return it.

=end doc

=cut

sub writePlainPassword
{
    my ($file) = (@_);

    #
    #  Pick a random passsword
    #
    my $pass = join( '', map {( 'a' .. 'z' )[rand 26]} 0 .. 12 );

    open( FILE, ">", $file ) or
      die "Failed to write to $file - $!";
    print FILE $pass . "\n";
    close(FILE);

    return ($pass);
}


1;


