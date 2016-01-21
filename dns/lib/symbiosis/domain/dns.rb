require 'symbiosis/domain/dkim'

module Symbiosis

  class Domain

    #
    # This now returns false as the service has been withdrawn.
    #
    def uses_bytemark_antispam?
      false
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
        # We encode just the first line.
        line = spf.split($/).first

        # But we make sure we remove any trailing \r, or \n characeters
        line = line.tr( "\n\r", "" )

        tinydns_encode(line)
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

    def dmarc_enabled?
      dmarc_record.is_a?(String)
    end

    alias has_dmarc? dmarc_enabled?

    #
    # Returns a DMARC record, based on various arguments in config/dmarc
    #
    def dmarc_record
      raw_dmarc = get_param("dmarc", self.config_dir)

      return nil unless raw_dmarc

      return 'v=DMARC1; p=quarantine; sp=none' if true == raw_dmarc

      #
      # Make sure we're not matching against things other than strings.
      #
      return nil unless raw_dmarc.is_a?(String)

      if raw_dmarc =~ /^(v=DMARC\d(;\s+\S+=[^;]+)+)/
        # Take this as a raw record
        return tinydns_encode($1)
      end

      puts "\tThe DMARC record looks wrong: #{raw_dmarc.inspect}" if $VERBOSE
      return nil
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
