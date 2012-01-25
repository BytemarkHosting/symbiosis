require 'linux/netlink/route'
require 'socket'
require 'resolv-replace'
require 'symbiosis/ipaddr'

module Symbiosis

  class Host 

    BYTEMARK_RANGES = %w(80.68.80.0/20 89.16.160.0/19 212.110.160.0/19 46.43.0.0/18 91.223.58.0/24 213.138.96.0/19 2001:41c8::/32).collect{|i| IPAddr.new(i)}

    BACKUP_SPACE_FILENAME = "/etc/symbiosis/dns.d/backup.name"

    #
    # Checks to see if an IP is in the Bytemark ranges.
    #
    def self.is_bytemark_ip?(ip)
      BYTEMARK_RANGES.any?{|range| range.include?(IPAddr.new(ip.to_s))}
    end

    #
    # Returned a cached netlink socket.
    #
    def self.netlink_socket
      @netlink_socket ||= Linux::Netlink::Route::Socket.new
    end

    #
    # Returns all IP addresses in use by a machine, in the order they were
    # configured on the interfaces, as an array of IPAddr objects.
    #
    def self.ip_addresses
      ip_addresses = []
      
      #
      # We only want addresses associated with the primary interface.
      #
      interface = self.primary_interface
      return [] if interface.nil?

      #
      # Call ip with a set of arguments that returns an easy-to-parse list of
      # IPs, for both IPv4 and 6, for the primary interface, with global scope.
      #
      netlink_socket.addr.list(:index => interface.index) do |ifaddr|
        next unless 0 == ifaddr.scope
        if ifaddr.respond_to?("local") and ifaddr.local.is_a?(::IPAddr)
          ip_addresses << IPAddr.new(ifaddr.local.to_s)
        else
          ip_addresses << IPAddr.new(ifaddr.address.to_s)
        end
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
    # Returns all IPv6 ranges
    #
    def self.ipv6_ranges
      ipv6_ranges = []

      #
      # Find the primary interface.
      #
      interface = self.primary_interface
      return ipv6_ranges if interface.nil?

      netlink_socket.addr.list(:index => interface.index, :family=>Socket::AF_INET6) do |ifaddr|
        next unless 0 == ifaddr.scope
        ipv6_ranges << IPAddr.new(ifaddr.address.to_s+"/"+ifaddr.prefixlen.to_s)
      end

      ipv6_ranges
    end

    #
    # Returns the "primary" IP of the machine.  This is assumed to be the
    # address with the smallest prefix.  If there is more than one with the
    # same prefix, then we take the first. 
    #
    def self.primary_ip(conditions = {})
      interface = self.primary_interface
      
      return nil if interface.nil?

      candidates = []      

      #
      # Select addresses based on conditions
      #
      # We only want the primary interface.
      conditions[:index] = interface.index

      netlink_socket.addr.list(conditions) do |ifaddr|
        next unless 0 == ifaddr.scope

        if ifaddr.respond_to?("local") and ifaddr.local.is_a?(::IPAddr)
          this_ip = IPAddr.new(ifaddr.local.to_s)
        else
          this_ip = IPAddr.new(ifaddr.address.to_s)
        end

        candidates << [this_ip, ifaddr.prefixlen.to_i]
      end

      winner = candidates.inject(nil) do |best, current|
        # If this is the first then return the current  
        if best.nil?
          current
        # IPv4 is preferred to IPv6 
        elsif current[0].ipv4? and best[0].ipv6?
          current 
        # IPv4 is preferred to IPv6 
        elsif current[0].ipv6? and best[0].ipv4?
          best
        # Smaller prefix wins
        elsif current[1] < best[1]
          current
        # Otherwise return the best (This should never happen!)
        else
          best
        end
      end

      return nil if winner.nil? or winner.empty?

      return winner[0]
    end

    #
    # Return the primary IPv4 address
    #
    def self.primary_ipv4
      self.primary_ip(:family => Socket::AF_INET)
    end
   
    #
    # Return the primary IPv6 address
    #
    def self.primary_ipv6
      self.primary_ip(:family => Socket::AF_INET6)
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
    def self.primary_backup_space(backup_space_filename=BACKUP_SPACE_FILENAME)
      if File.exists?(backup_space_filename)
        File.open(backup_space_filename){|fh| fh.readlines}.first.to_s.chomp
      else
        self.backup_spaces.first
      end
    end

    
    # Returns the primary interface for the machine as an Linux::Netlink::Link
    # object.
    #
    # We can define the primary interface as the one with the default route.
    #
    # We match on scope == 0 (RT_SCOPE_UNIVERSE) and type == 1 (RTN_UNICAST)
    # and gateway != nil
    #
    def self.primary_interface
      route = self.netlink_socket.route.read_route.select do |rt|
        rt.scope == 0 and rt.type == 1 and !rt.gateway.nil?
      end.sort{|a,b| a.oif <=> b.oif}.first

      return nil if route.nil?

      #
      # Bit of an omission.  Need for the #find method.
      #
      self.netlink_socket.link.extend(Enumerable)

      primary_interface = self.netlink_socket.link.find{|l| route.oif == l.index }

      return primary_interface
    end

    #
    # Add a /32 or /128 to the primary interface.
    #
    def self.add_ip(ip)
      interface = self.primary_interface

      #
      # Make sure the IP address is fully masked.
      #
      ip = ip.mask((ip.ipv4? ? 32 : 128))

      raise ArgumentError, "Unable to find primary interface" if interface.nil?

      #
      # Don't add IPs that already exist.
      #
      raise Errno::EEXIST, ip.to_s if self.ip_addresses.include?(ip)

      @netlink_socket.addr.add(
        :index=>interface.index.to_i,
        :local=>ip.to_s,
        :prefixlen=>ip.prefixlen
      )

      return nil
    end

  end

end


