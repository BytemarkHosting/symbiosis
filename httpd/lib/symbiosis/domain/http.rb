require 'symbiosis/domain'

module Symbiosis

  class Domain
    #
    # Checks to see if a domain should have statistics generated for it.
    # Returns true if statistics should be generated, false if not.
    #
    def should_have_stats?
      get_param('stats', self.config_dir) != false
    end

    #
    # Sets the domain to have statistics generated, or not.  Expects true if
    # statistics are wanted, or false if not.
    #
    def should_have_stats=(bool)
      return ArgumentError, "Expecting true or false" unless [TrueClass, FalseClass].include?(bool.class)

      set_param("stats", bool, self.config_dir)
    end

    #
    # Returns the directory where stats files should be kept.  Defaults to
    # stats inside the htdocs_dir
    #
    def stats_dir
      File.join(self.htdocs_dir, "stats")
    end

    #
    # Returns the directory where HTML documents are served from.  Defaults to
    # public/htdocs
    #
    def htdocs_dir
      File.join(self.public_dir, "htdocs")
    end

    #
    # Return the directory where CGI executables are server
    #
    def cgibin_dir
      File.join(self.public_dir, "cgi-bin")
    end

    #
    # This returns a Symbiosis::ConfigFiles::Apache object for this domain.
    #
    def apache_configuration(ssl_template, non_ssl_template, apache2_dir='/etc/apache2')
      #
      # Sets up the config file name
      #
      config_file   = File.join(apache2_dir, "sites-available","#{self.name}.conf")
      config        = Symbiosis::ConfigFiles::Apache.new(config_file, "#")
      config.domain = self

      document_root = File.join(self.directory,"public","htdocs")

      unless File.directory?(document_root)
        verbose "\tThe document root #{document_root} does not exist."
        return nil
      end

      #
      #  If SSL is not enabled then we can skip
      #
      if ( self.ssl_enabled? )
        begin
          self.ssl_verify
          config.template = ssl_template

          verbose "\tSSL is enabled -- using SSL template"

        rescue OpenSSL::OpenSSLError => err
          #
          # This catches any OpenSSL problem, and allows us to revert to non-ssl hosting.
          #
          warn "SSL configuration for #{self.name} is broken -- #{err.to_s} (#{err.class.to_s})"

          if self.ssl_mandatory?
            #
            # If this domain is SSL-only, do not reconfigure it with the non-SSL
            # template.
            #
            verbose "\tSSL is enabled and mandatory, but mis-configured.  Skipping."
            return nil
          end

          verbose "\tSSL is enabled but mis-configured -- using non-SSL template."
          config.template = non_ssl_template
        end
      else
        config.template = non_ssl_template

        verbose "\tSSL is not enabled -- using non-SSL template"
      end


      return config
    end

  end

end
