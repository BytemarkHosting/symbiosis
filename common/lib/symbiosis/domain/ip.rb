module Symbiosis

  class Domain

    #
    # This returns the primary IP if a domain has no IP explicitly set, or if
    # the IP set is "wrong" in some way, and cannot be parsed.
    # 
    def ip
      ip_param = get_param("ip")
      
      return nil unless ip_param.is_a?(String)

      begin
        ip = IPAddr.new(ip_param.chomp.trim)
      rescue ArgumentError => err
        puts err.to_s
        return nil
      end

      return ip
    end

    #
    # This returns the IPv6 address if one has been set, or nil otherwise.
    #
    def ipv6
      ipv6_param = get_param("ipv6")

      return nil unless ipv6_param.is_a?(String)

      begin
        ipv6 = IPAddr.new(ipv6_param.chomp.trim)
      rescue ArgumentError => err
        puts err.to_s
        return nil
      end

      return ipv6
    end

    #
    # This writes the new IP.
    #
    def ip=(new_ip)
      set_param("ip", new_ip.to_s)
    end

    #
    # 
    #
    def ipv6=(new_ipv6)
      set_param("ipv6", new_ip.to_s)
    end

  end

end


