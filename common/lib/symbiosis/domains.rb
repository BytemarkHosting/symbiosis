# symbiosis/domains.rb
#
# This code is released under the same terms as Ruby itself.  See LICENCE for
# more details.
#
# (c) 2010 Bytemark Computer Consulting Ltd
#


class Symbiosis

  #
  # A class for working with domains
  #
  class Domains

    #
    # Class variables
    #
    # * prefix is the location of doamins.
    #
    attr_reader :prefix


    #
    # The constructor
    #
    def initialize( prefix = "/srv" )
      @prefix = prefix
    end

    #
    # An iterator for each domain.
    #
    def each(&block)
      domains().each(&block)
    end

    #
    # Return each domain name
    #
    def domains

      #
      #  For each domain.
      #
      Dir.foreach( @prefix ) do |domain|
        if ( domain !~ /^\./ )
          push domains,domain
        end
      end

      domains
    end

  end
end
