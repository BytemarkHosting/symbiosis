require 'symbiosis/domain'

module Symbiosis

  #
  # A class for working with domains
  #
  class Domains

    #
    # Find all domains, and iterate over each one.
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
      #
      # make capital letters lower-case.
      #
      domain = domain.to_s.downcase

      #
      # Sanity check name.
      #
      return nil unless domain =~ Symbiosis::Domain::NAME_REGEXP

      #
      # Search all domains.  This returns a maximum of two results -- one with
      # www. and one without, assuming /srv/www.domain and /srv/domain both
      # exist.
      #
      # Check for domain, and (random.prefix.)?www.domain.
      #
      possibles = [domain, domain.sub(/^(.*\.)?www\./,"")].collect do |possible|
        dir = File.join(prefix, possible)
        next unless File.directory?(dir)

        begin
          Domain.from_directory(dir)
        rescue ArgumentError => err
          warn err.to_s
        end

      end.compact

      #
      # Nothing found, return nil
      #
      return nil if possibles.length == 0

      #
      # Return the one and only result.
      #
      return possibles.first if possibles.length == 1

      #
      # OK now match the nearest domain, breaking the domain down by dots.
      #
      until domain.nil?
        match = possibles.find{|d| d.name == domain}
        return match unless match.nil?

        #
        # Split the domain into a prefix, and the remainder.
        #
        prefix, domain = domain.split(".",2)
      end

      return nil
    end

    #
    # Find all domains in prefix.  Returns an array of Symbiosis::Domain
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
        # Sanity check name.
        #
        next unless domain =~ Symbiosis::Domain::NAME_REGEXP

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
