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

  end

end

