# Symbiosis module
module Symbiosis
  # SSL subclass
  class SSL
    # Runs the SSL hooks for symbiosis-ssl when
    # domains' certificate sets are altered
    class Hooks
      HOOKS_GLOB = '/symbiosis/ssl-hooks.d/*'.freeze

      def self.run!(event, domains)
        Hooks.new.run!(event, domains)
      end

      def initialize(hooks_glob = Symbiosis.path_in_etc(HOOKS_GLOB))
        @hooks_glob = hooks_glob
      end

      def run!(event, domains)
        @event = event
        @domains = domains

        Dir.glob(@hooks_glob)
           .select { |h| valid_hook?(h) }
           .all? { |h| runs_successfully?(h) }
      end

      def valid_hook?(hook)
        File.executable?(hook) &&
          File.basename(hook) =~ /^[a-zA-Z0-9_-]+$/
      end

      private

      def runs_successfully?(script)
        opts = { stdin_data: @domains.join("\n") + "\n" }
        output, status = Open3.capture2e(script, @event, opts)
        return true if status.success?
        puts script_status(script, output, status)
        false
      end

      def script_status(script, output, status)
        "============================================\n" \
        "Error executing SSL script for #{@event} event\n" \
        "#{script} exited with status #{status.exitstatus}\n" \
        "#{output}\n\n"
      end
    end
  end
end
