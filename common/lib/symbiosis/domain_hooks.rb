require 'symbiosis'

module Symbiosis
  # generic hooks implementation
  # use subclasses to provide default behaviour
  # see Symbiosis::DomainSkeleton::Hooks
  # and Symbiosis::SSL::Hooks
  class DomainHooks
    def initialize(hooks_dir)
      @hooks_dir = hooks_dir
    end

    def run!(event, domains)
      @event = event
      @domains = domains

      Dir.glob(File.join(@hooks_dir, '*'))
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
      "Error executing script for #{@event} event\n" \
      "#{script} exited with status #{status.exitstatus}\n" \
      "#{output}\n\n"
    end
  end
end
