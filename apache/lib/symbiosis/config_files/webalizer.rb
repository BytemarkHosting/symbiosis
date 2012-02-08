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

      #
      # This method returns the location of the Webalizer "history" file, used
      # to keep the last 12 months-worth of stats, for use in the HistoryName
      # directive.
      #
      # Older machines will have it at public/htdocs/stats/webalizer.hist,
      # newer ones at config/.webalizer.hist.
      #
      # It will default to the new location if nothing is found at the old
      # location.
      #
      def history_name
        #
        # This is the old place.
        #
        old_location = File.join(domain.stats_dir, "webalizer.hist")
        return old_location if File.exists?(old_location)

        #
        # OK, just use the new one.
        #
        return File.join(domain.config_dir, ".webalizer.hist")
      end

      #
      # This method returns the location of the Webalizer "current" file, used
      # for incremental stats, for use in the IncrementalName directive.
      #
      # Older machines will have it at public/htdocs/stats/webalizer.current,
      # newer ones at config/.webalizer.current.
      #
      # It will default to the new location if nothing is found at the old
      # location.
      #
      def incremental_name
        #
        # This is the old place.
        #
        old_location = File.join(domain.stats_dir, "webalizer.current")
        return old_location if File.exists?(old_location)

        #
        # OK, just use the new one.
        #
        return File.join(domain.config_dir, ".webalizer.current")
      end

    end

  end

end


