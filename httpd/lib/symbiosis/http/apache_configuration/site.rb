module Symbiosis
  module HTTP
    # configures apache mass-hosting and sites
    module ApacheConfiguration
      # represents and produces a Symbiosis::ConfigFiles::Apache
      # for a particular site
      # TODO: this functionality should probably be merged into
      # Symbiosis::HTTP::Domain and Symbiosis::ConfigFiles::Apache
      class Site
        # domain should be a Symbiosis::HTTP::Domain
        def initialize(domain, apache2_dir = '/etc/apache2')
          @domain = domain
          @apache2_dir = apache2_dir
        end

        def config_file_path
          File.join(@apache2_dir, 'sites-available', "#{@domain.name}.conf")
        end

        # This returns a Symbiosis::ConfigFiles::Apache object for this domain.
        def make_config_object(ssl_template, non_ssl_template)
          # Sets up the config file name
          config = Symbiosis::ConfigFiles::Apache.new(config_file_path, '#')
          config.domain = @domain

          unless htdocs_exists?
            verbose "\tThe document root #{@domain.htdocs_dir} does not exist."
            return nil
          end

          #  If SSL is not enabled then we can skip
          config.template = choose_template(ssl_template, non_ssl_template)

          return nil if config.template.nil?

          config
        end

        private

        def ssl_ok?
          false unless @domain.ssl_enabled?

          @domain.ssl_verify
        rescue OpenSSL::OpenSSLError => err
          warn "SSL configuration for #{name} is broken -- " \
               "#{err} (#{err.class})"
          false
        end

        def choose_template_when_ssl_bad(non_ssl_template)
          if @domain.ssl_mandatory?
            verbose "\tSSL is enabled and mandatory, but mis-configured. " \
                    'Skipping.'
            return nil
          end

          verbose "\tSSL is enabled but mis-configured -- " \
                  'using non-SSL template.'
          non_ssl_template
        end

        def choose_template(ssl_template, non_ssl_template)
          if ssl_enabled? && ssl_ok?
            verbose "\tSSL is enabled -- using SSL template"
            ssl_template
          elsif ssl_enabled?
            choose_template_when_ssl_bad
          else
            verbose "\tSSL is not enabled -- using non-SSL template"
            non_ssl_template
          end
        end
      end
    end
  end
end
