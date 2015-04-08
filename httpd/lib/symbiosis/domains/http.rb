require 'symbiosis/config_files/apache'

module Symbiosis

  class Domains

    #
    # Returns true if this machine can have the zz-mass-hosting configuration
    # for apache generated.
    #
    def self.apache_mass_hosting_enabled?(prefix="/etc/symbiosis")
      File.exist?(File.join(prefix,"apache.d/disabled.zz-mass-hosting")) ? false : true
    end

    #
    # Returns true if automatic apache configuration is enabled.
    #
    def self.apache_configuration_enabled?(prefix="/etc/symbiosis")
      File.exist?(File.join(prefix,"apache.d/disabled")) ? false : true
    end

    #
    # Returns a site-wide apache config (zz-mass-hosting).
    #
    def self.apache_configuration(template, apache2_dir='/etc/apache2')
      basename             = File.basename(template, ".template.erb")
      sites_available_file = File.join(apache2_dir, "sites-available","#{basename}.conf")

      config          = Symbiosis::ConfigFiles::Apache.new(sites_available_file, "#")
      config.template = template

      return config
    end

  end

end
