require 'symbiosis/domain'

module Symbiosis
  module HTTP
    # Handles configuration of webalizer for a domain
    class Domain < Symbiosis::Domain

      def initialize(name = nil, prefix = Symbiosis::PREFIX)
        super
      end
      # Checks to see if a domain should have statistics generated for it.
      # Returns true if statistics should be generated, false if not.
      def should_have_stats?
        bool = get_param 'no-stats'

        # We invert the flag, since it is called "no-stats".
        return true if false == bool || bool.nil?

        # Return false if the flag exists at all.
        false
      end

      # Sets the domain to have statistics generated, or not.  Expects true if
      # statistics are wanted, or false if not.
      def should_have_stats=(bool)
        # Invert the setting, since it is called "no-stats"
        if bool
          set_param('no-stats', false)
        else
          set_param('no-stats', true)
        end

        bool
      end

      # Returns the directory where stats files should be kept.  Defaults to
      # stats inside the htdocs_dir
      def stats_dir
        File.join(htdocs_dir, 'stats')
      end

      # Returns the directory where HTML documents are served from.  Defaults to
      # public/htdocs
      def htdocs_dir
        File.join(@domain.public_dir, 'htdocs')
      end

      # Return the directory where CGI executables are server
      def cgibin_dir
        File.join(@domain.public_dir, 'cgi-bin')
      end

      # This returns a Symbiosis::ConfigFiles::Apache object for this domain.
      def apache_configuration(ssl_template, non_ssl_template, apache2_dir = '/etc/apache2')
        # Sets up the config file name
        config_file   = File.join(apache2_dir, 'sites-available', "#{name}.conf")
        config        = Symbiosis::ConfigFiles::Apache.new(config_file, '#')
        config.domain = self

        unless File.directory?(htdocs_dir)
          verbose "\tThe document root #{htdocs_dir} does not exist."
          return nil
        end

        #  If SSL is not enabled then we can skip
        if ssl_enabled?
          begin
            ssl_verify
            config.template = ssl_template

            verbose "\tSSL is enabled -- using SSL template"
          rescue OpenSSL::OpenSSLError => err
            # This catches any OpenSSL problem, and allows us to revert to non-ssl hosting.
            warn "SSL configuration for #{name} is broken -- #{err} (#{err.class})"

            if ssl_mandatory?
              # If this domain is SSL-only, do not reconfigure it with the non-SSL
              # template.
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

        config
      end
    end
  end
end
