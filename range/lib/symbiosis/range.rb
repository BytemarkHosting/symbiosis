
require 'ipaddr'
require 'pp'
require 'socket'
require 'resolv-replace'

module Symbiosis

  class Range

    BYTEMARK_RANGES = %w(80.68.80.0/20 89.16.160.0/19 212.110.160.0/19 46.43.0.0/18 91.223.58.0/24 213.138.96.0/19 2001:41c8::/32).collect{|i| IPAddr.new(i)}

    BACKUP_SPACE_FILENAME = "/etc/symbiosis/dns.d/backup.name"

    #
    # Checks to see if an IP is in the Bytemark ranges.
    #
    def self.is_bytemark_ip?(ip)
      BYTEMARK_RANGES.any?{|range| range.include?(IPAddr.new(ip.to_s))}
    end

    #
    # Returns all IP addresses in use by a machine, in the order they were
    # configured on the interfaces, as an array of IPAddr objects.
    #
    def self.ip_addresses
      ip_addresses = []
      #
      # Call ip with a set of arguments that returns an easy-to-parse list of
      # IPs, for both IPv4 and 6.
      #
      (IO.popen("/bin/ip -o -f inet  addr show scope global"){|pipe| pipe.readlines} +
       IO.popen("/bin/ip -o -f inet6 addr show scope global"){|pipe| pipe.readlines}).each do |l|
        next unless l =~ /inet6? ((\d{1,3}\.){3,3}\d{1,3}|[0-9a-f:]+)/
        ip_addresses << IPAddr.new($1)
      end
      ip_addresses
    end

    #
    # Returns all global IPv4 addresses in use by a machine, as an array of
    # IPAddr objects.
    #
    def self.ipv4_addresses
      self.ip_addresses.select{|ip| ip.ipv4?}
    end

    #
    # Returns all global IPv6 addresses in use by a machine, as an array of
    # IPAddr objects.
    #
    def self.ipv6_addresses
      self.ip_addresses.select{|ip| ip.ipv6?}
    end

    #
    #
    # Returns the "primary" IP of the machine.  This is assumed to be the first
    # globally routable IPv4 address of the first interface in the list
    # returned by the "ip addr" command above.
    #
    def self.primary_ip
      self.ipv4_addresses.first
    end

    def self.primary_bytemark_ip
      self.ipv4_addresses.find{|ip| self.is_bytemark_ip?(ip)}
    end

    #
    # Returns an array of backup spaces name given the IP addresses of the
    # machine.  Returns an empty array if the argument is invalid, or if the
    # argument is not a Bytemark IP.  IPv6 capable.
    #
    def self.backup_spaces(ips = self.ip_addresses)
      # No Bytemark IP found?
      ips = [ips] unless ips.is_a?(Array)
      spaces = []
      ips.each do |ip|
        begin
          ip = IPAddr.new(ip) if ip.is_a?(String)
        rescue ArgumentError => err
          # This will be caught in the next conditional.
        end

        # Check to make sure we have an IP
        if !ip.is_a?(IPAddr)
          warn "'#{ip}' is not an IP Address." if $VERBOSE
          next
        end

        # Make sure it is a Bytemark IP
        if !self.is_bytemark_ip?(ip)
          warn "IP #{ip} is not in the Bytemark ranges." if $VERBOSE
          next
        end

        # Form the reverse lookup string
        lookup = ip.reverse.gsub(/(ip6|in-addr).arpa\Z/,"backup-reverse.bytemark.co.uk")

        warn "Doing lookup of #{lookup} for #{ip}..." if $VERBOSE

        # Do the lookup
        begin
          Resolv::DNS.open do |dns|
            res = dns.getresources(lookup, Resolv::DNS::Resource::IN::TXT)
            warn "DNS returned #{res.length} results." if $VERBOSE
            spaces += res.collect{|rr| rr.strings}.flatten
          end
        rescue Resolv::ResolvTimeout, Resolv::ResolvError => err
          warn "Look up of #{lookup} failed -- #{err.to_s}"
        end
      end
      spaces.uniq
    end

    #
    # This returns the primary backup space.  This is defined as the first in
    # the list returned by backup_spaces OR whatever is contained in a file
    # called /etc/symbiosis/dns.d/backup.name
    #
    def self.primary_backup_space
      if File.exists?(BACKUP_SPACE_FILENAME)
        File.open(BACKUP_SPACE_FILENAME){|fh| fh.readlines}.first.to_s.chomp
      else
        self.backup_spaces.first
      end
    end
  end

end


