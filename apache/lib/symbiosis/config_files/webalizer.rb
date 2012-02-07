require 'symbiosis/config_file'
require 'tempfile'

module Symbiosis
  module ConfigFiles
    class Webalizer < Symbiosis::ConfigFile
      # This is just a standard config.
      #
      # TODO: Need an OK? check.
      #
      def ok?
        true
      end

      def write(config = self.generate_config, opts = {})
        #
        # Set the UID/GID when writing the file.
        #
        opts[:uid] = domain.uid unless opts.has_key?(:uid)
        opts[:gid] = domain.gid unless opts.has_key?(:gid)

        super
      end
    end
  end
end


