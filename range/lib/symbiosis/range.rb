
require 'ipaddr'

module Symbiosis

  class Range

    BYTEMARK_RANGES = %w(80.68.80.0/20 89.16.160.0/20 212.110.160.0/19 2001:41c8::/32).collect{|i| IPAddr.new(i)}

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
    # Returns all global IPv4 addresses in use by a machine, as an array of
    # IPAddr objects.
    #
    def self.ipv6_addresses
      self.ip_addresses.select{|ip| ip.ipv6?}
    end

  end

end


