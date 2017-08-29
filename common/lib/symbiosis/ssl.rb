require 'symbiosis'
require 'open3'

module Symbiosis
  # SSL knows about which SSL providers exist and provides SSL helper functions
  class SSL
    PROVIDERS ||= []

    def self.call_hooks(domains_with_updates, event)
      hooks_path = Symbiosis.path_in_etc('/symbiosis/ssl-hooks.d/*')
      success = true

      Dir.glob(hooks_path).each do |script|
        next unless File.executable?(script)
        next if File.basename(script) =~ /^[a-zA-Z0-9_-]+$/

        success &&= run_hook_script(event, script, domains_with_updates)
      end
      success
    end

    def self.run_hook_script(event, script, domains_with_updates)
      opts = { stdin_data: domains_with_updates.join("\n") }
      output, status = Open3.capture2e([script, event], opts)

      return true if status.success?

      puts "============================================\n"
      puts "Error executing SSL script for #{event} hook\n"
      puts "#{script} exited with status #{status.exitstatus}\n"
      puts output + "\n\n"
      false
    end
  end
end
