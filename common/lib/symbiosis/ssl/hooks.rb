# Symbiosis module
module Symbiosis
  # SSL submodule
  module SSL
    # Runs the SSL hooks for symbiosis-ssl when
    # domains' certificate sets are altered
    class Hooks
      HOOKS_GLOB = '/symbiosis/ssl-hooks.d/*'.freeze

      def self.run!(event, domains)
        Hooks.new.run_hooks(event, domains)
      end

      def initialize(hooks_glob = Symbiosis::DefaultDirs.path_in_etc(HOOKS_GLOB))
        @hooks_glob = hooks_glob
      end

      def run!(event, domains)
        @event = event
        @domains = domains

        Dir.glob(@hooks_dir)
           .filter(valid_hook?)
           .all?(runs_successfully?)
      end

      def valid_hook?(hook)
        File.executable?(hook) &&
          File.basename(hook) =~ /^[a-zA-Z0-9_-]+$/
      end

      private

      def runs_successfully?(hook)
        opts = { stdin_data: @domains.join("\n") }
        output, status = Open3.capture2e([hook, event], opts)

        return true if status.success?
        puts hook_status(output, status)
        false
      end

      def hook_status(output, status)
        "============================================\n" \
        "Error executing SSL script for #{@event} hook\n" \
        "#{script} exited with status #{status.exitstatus}\n" \
        "#{output}\n\n"
      end
    end
  end
end
