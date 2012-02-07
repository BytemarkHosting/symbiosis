require 'symbiosis/domain'

module Symbiosis

  class Domain
    #
    # Checks to see if a domain should have statistics generated for it.
    # Returns true if statistics should be generated, false if not.
    #
    def should_have_stats?
      bool = get_param("no-stats", self.config_dir)

      #
      # We invert the flag, since it is called "no-stats".
      #
      return true if false == bool or bool.nil?

      #
      # Return false if the flag exists at all.
      #
      return false
    end

    #
    # Sets the domain to have statistics generated, or not.  Expects true if
    # statistics are wanted, or false if not.
    #
    def should_have_stats=(bool)
      return ArgumentError, "Expecting true or false" unless [TrueClass, FalseClass].include?(bool.class)

      #
      # Invert the setting, since it is called "no-stats"
      #
      if true == bool
        set_param("no-stats", false, self.config_dir)
      else 
        set_param("no-stats", true, self.config_dir)
      end

      return bool
    end

    #
    # Returns the directory where stats files should be kept.  Defaults to
    # public/htdocs/stats.
    #
    def stats_dir
      File.join(domain.directory, "public", "htdocs", "stats")
    end

  end

end
