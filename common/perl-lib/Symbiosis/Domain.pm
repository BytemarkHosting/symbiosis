
=head1 NAME

Symbiosis::Domain - A module for working with a single Symbiosis domain.

=head1 SYNOPSIS

=for example begin

    #!/usr/bin/perl -w

    use Symbiosis::Domain;
    use strict;

    my $helper     = Symbiosis::Domain->new( path => '/srv/example.com' );

    # more code.

=for example end


=head1 DESCRIPTION

This module contains code for working with a single Symbiosis domain.

=cut

=head1 FTP LOGINS

For a domain to be enabled for FTP there are three ways you can save
the passwrod in /srv/example.com/config/ftp-password:

=over 8

=item As plaintext
For example you could write "blah" in the password.

=item As a crypted string.
Using the Perl crypt function.

=item As an MD5 digest.
For example "echo -n 'my password' | md5sum"

=back

Each of these will be tested in turn.

=cut


package Symbiosis::Domain;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);


require Exporter;
require AutoLoader;

@ISA    = qw(Exporter AutoLoader);
@EXPORT = qw();

($VERSION) = "1.1";



#
#  Standard modules which we require.
#
use strict;
use warnings;


use Digest::MD5;
use File::Basename;



=head2 new

Create a new instance of this object.

=cut

sub new
{
    my ( $proto, %supplied ) = (@_);
    my $class = ref($proto) || $proto;

    my $self = {};

    #
    #  Allow user supplied values to override our defaults
    #
    foreach my $key ( keys %supplied )
    {
        $self->{ lc $key } = $supplied{ $key };
    }

    bless( $self, $class );
    return $self;

}


=begin doc

Return the domain name.

=end doc

=cut

sub name
{
    my ($self) = (@_);

    my $path = $self->{ 'path' } || die "No path given in constructor";

    return ( basename($path) );
}


=begin doc

Return the path to the domain.

=end doc

=cut

sub path
{
    my( $self ) = ( @_ );

    my $path = $self->{ 'path' } || die "No path given in constructor";

    return ( $path );

}


=begin doc

Does this domain exist?

=end doc

=cut

sub exists
{
    my ($self) = (@_);

    my $path = $self->{ 'path' } || die "No path given in constructor";

    return ( -d $path );
}


=begin doc

Does this domain appear to be setup for an FTP login?

=end doc

=cut

sub isFTP
{
    my ($self) = (@_);

    my $path = $self->{ 'path' } || die "No path given in constructor";

    return ( -e $path . "/config/ftp-password" );

}


=begin doc

Given an FTP password test to see if this matches reality.

=end doc

=cut

sub loginFTP
{
    my ( $self, $passwd ) = (@_);

    #
    #  Empty passwords are forbidden.
    #
    return 0 if ( !defined($passwd) || !length($passwd) );

    #
    #  If the domain isn't setup for FTP then we cannot
    # be correct.
    #
    return 0 if ( !$self->isFTP() );

    #
    #  OK now read the pssword
    #
    open( my $handle, "<", $self->{ 'path' } . "/config/ftp-password" ) or
      return 0;

    my $password = <$handle> || undef;
    close($handle);

    #
    #  Failed?  Then login is failed.
    #
    return 0 unless ( defined($password) && length($password) );

    #
    #  Remove trailing newline if present.
    #
    chomp($password);

    #
    #  OK we have read a password.  We have two cases,
    # a plaintext password and a crypt password.
    #
    if ( $password eq $passwd )
    {
        return 1;
    }

    #
    #  Did we read a crypted password?
    #
    if ( $password =~ /^(?:{CRYPT})?([0-9a-z\$.\/]+)$/i )
    {
        my ( $salt, $hash ) = ( $1, $2 );

        if ( $salt && $hash && ( crypt( $password, $salt ) eq $hash ) )
        {
            return 1;
        }
    }

    #
    #  Final option - MD5 sum
    #
    my $ctx = Digest::MD5->new();
    $ctx->add($passwd);

    #
    #  Compare the hex digits
    #
    if ( lc( $ctx->hexdigest() ) eq lc($password) )
    {
        return 1;
    }

    #
    #  All three methods failed.
    #
    return 0;
}



#
#  End of module
#
1;

