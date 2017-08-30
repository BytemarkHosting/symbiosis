require 'symbiosis/domain'

module Symbiosis
  module HTTP
    # Handles configuration of webalizer for a domain
    class Domain < Symbiosis::Domain
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

      def htdocs_exists?
        File.directory?(htdocs_dir)
      end
    end
  end
end
