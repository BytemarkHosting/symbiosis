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

    def dmarc_enabled?
      dmarc_record.is_a?(String)
    end

    alias has_dmarc? dmarc_enabled?

    #
    # Returns a DMARC record, based on various arguments in config/dmarc
    #
    def dmarc_record
      raw_dmarc = get_param("dmarc", self.config_dir)

      unless raw_dmarc
        return nil
      end

      if raw_dmarc.is_a?(String) and raw_dmarc =~ /^v=DMARC\d;(\w+=[^;]+;)+/
        # Take this as a raw record
        return raw_dmarc.split($/).first
      end

      has_antispam = get_param("antispam", self.config_dir)

      dmarc_hash = {
        "v" => "DMARC1",
        "p" => "quarantine",
        "adkim" => (self.has_dkim? ? "s" : nil),
        "aspf" => (self.has_spf? ? "s" : nil),
        "sp" => "none",
        "pct" => "100" 
      }.reject{|k,v| v.nil?}

      # 
      # raw_dmarc = raw_dmarc.to_s.split($/)
      #
      # raw_dmarc.each do |line|
      #   if /\b([A-Za-z0-9]+)\s*=\s*(\w+);?/
      #       dmarc_hash[$1.downcase] = $2
      #   end
      # end

      dmarc = ["v="+dmarc_hash.delete("v")]
      dmarc += dmarc_hash.sort.collect{|k,v| "#{k}=#{v}"}

      return tinydns_encode(dmarc.join(";"))
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

