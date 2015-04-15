require 'symbiosis/domain/dkim'

module Symbiosis

  class Domain
    #
    # Fetches the Bytemark anti-spam flag.  Returns true or false.  This causes
    # the DNS template to be changed to point the MX records at the Bytemark
    # anti-spam service, as per http://www.bytemark.co.uk/nospam .  Also the
    # Exim4 config checks for this flag, and will defer mail that doesn't come
    # via the anti-spam servers.
    #
    #
    #
    def uses_bytemark_antispam? 

      value = get_param("bytemark-antispam", self.config_dir)

      #
      # Return false if get a "false" or "nil"
      #
      return false if false == value or value.nil?

      #
      # Otherwise it's true!
      #
      return true
    end

    #
    # Sets the Bytemark anti-spam flag.  Expects true or false.
    #
    def use_bytemark_antispam=(value)
      raise ArgumentError, "expecting true or false" unless value.is_a?(TrueClass) or value.is_a?(FalseClass)
      set_param("bytemark-antispam", value, self.config_dir)
    end

    #
    # Returns true if a domain has SPF enabled.
    #
    def spf_enabled?
      spf_record.is_a?(String)
    end

    alias has_spf? spf_enabled?

    def spf_record
      spf = get_param("spf", self.config_dir)
      spf = "v=spf1 +a +mx ?all" if spf === true

      if spf.is_a?(String)
       tinydns_encode(spf)
      else
        nil
      end
    end

    def srv_record_for(priority, weight, port, target)
      data =  ([priority, weight, port].pack("nnn").bytes.to_a +
              target.split(".").collect{|x| [x.length, x]} +
              [ 0 ]).flatten
      data.collect{|x| tinydns_encode(x)}.join
    end

    #
    # Returns the DNS TTL as defined in config/ttl, or 300 if no TTL has been set.
    #
    def ttl
      ttl = get_param("ttl", self.config_dir)
      if ttl.is_a?(String) and ttl =~ /([0-9]+)/
        begin
          ttl = Integer($1)
        rescue ArgumentError
          ttl = 300
        end
      else
        ttl = 300
      end

      if ttl < 60
        ttl = 60
      elsif ttl > 86400
        ttl = 86400
      end

      ttl
    end

    private

    #
    # Encodes a given string into a format suitable for consupmtion by TinyDNS
    #
    def tinydns_encode(s)
      s = [s].pack("c") if (s.is_a?(Integer) and 255 > s)

      s.chars.collect{|c| c =~ /[\w .=+;?-]/ ? c : c.bytes.collect{|b| "\\%03o" % b}.join}.join
    end

    #
    # Decodes a given string from a format suitable for consupmtion by TinyDNS
    # 
    def tinydns_decode(s)
      s.gsub(/(?:\\([0-7]{3,3})|.)/){|r| $1 ? [$1.oct].pack("c*") : r}
    end


  end

end

