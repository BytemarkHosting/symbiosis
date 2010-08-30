# -*- cperl -*- #

=head1 NAME

Symbiosis::Domains - A module for working with a Symbiosis host.

=head1 SYNOPSIS

=for example begin

    #!/usr/bin/perl -w

    use Symbiosis::Domains;
    use strict;

    my $helper  = Symbiosis::Domains->new( prefix => '/srv' );

    my @domains = $helper->getDomains();

=for example end


=head1 DESCRIPTION

This module contains code for working with a Symbiosis host.

=cut


package Symbiosis::Domains;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);


require Exporter;
require AutoLoader;

@ISA    = qw(Exporter AutoLoader);
@EXPORT = qw();

($VERSION) = '$Revision: 1.69 $' =~ m/Revision:\s*(\S+)/;



#
#  Standard modules which we require.
#
use strict;
use warnings;
use File::Basename;

#
#  Our modules
#
use Symbiosis::Domain;



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

Return an array of Symbiosis::Domain objects for each domain upon
this host.

=end doc

=cut

sub getDomains
{
    my ($self) = (@_);

    my $prefix = $self->{ 'prefix' } || "/srv";


    my @results;


    foreach my $dir ( sort( glob( $prefix . "/*" ) ) )
    {

        #
        #  Skip dotfiles.
        #
        my $name = basename($dir);
        next if ( $name =~ /^\./ );

        #
        #  Skip non-directories
        #
        next if ( !-d $dir );

        #
        #  Create a new domain object and save it away.
        #
        my $domain = Symbiosis::Domain->new( path => $dir );
        push( @results, $domain );
    }

    return (@results);
}


#
#  End of module
#
1;

