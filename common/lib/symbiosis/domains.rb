# symbiosis/domains.rb
#
# This code is released under the same terms as Ruby itself.  See LICENCE for
# more details.
#
# (c) 2010 Bytemark Computer Consulting Ltd
#

require 'symbiosis/domain'

module Symbiosis

  #
  # A class for working with domains
  #
  class Domains

    #
    # An iterator for each domain.
    #
    def self.each(prefix="/srv",&block)
      all(prefix).each(&block)
    end

    #
    # Does the specified domain exist on this system?
    #
    def self.include?(domain, prefix="/srv")
      all(prefix).find(domain).is_a?(Domain)
    end

    #
    # Finds a domain.  Returns either a Domain, or nil if nothing was found.
    #
    def self.find(domain, prefix="/srv")
      return nil unless domain.to_s =~ /^([a-z0-9\-]+\.?)+$/
      all(prefix).find{|d| d.name =~ /^#{domain}$/i}
    end

    #
    # Return each domain name
    #
    def self.all(prefix = "/srv")
      results = Array.new

      #
      #  For each domain.
      #
      Dir.glob( File.join(prefix,"*") ) do |entry|
        #
        # Only interested in directories
        #
        next unless File.directory?(entry)

        this_prefix, domain = File.split(entry)
        #
        # Don't want dotfiles.
        #
        next if domain =~ /^\./ 

        begin
          results << Domain.new(domain, this_prefix)
        rescue ArgumentError => err
          warn err.to_s
        end
      end

      results
    end

  end
end
