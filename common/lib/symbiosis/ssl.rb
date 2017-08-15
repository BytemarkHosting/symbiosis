require 'symbiosis'

module Symbiosis
  # SSL knows about which SSL providers exist and provides SSL helper functions
  class SSL
    PROVIDERS ||= []

    def self.call_hooks(domains_with_updates, event)
      return if domains_with_updates.empty?

      hooks_path = Symbiosis.path_in_etc('/symbiosis/ssl-hooks.d/*')

      Dir.glob(hooks_path).each do |script|
        next unless File.executable?(script)
        next if File.basename(script) =~ /\..*$/
        IO.popen([script, event], 'r+') do |io|
          io.puts domains_with_updates.join("\n")
          io.close_write # Close the pipe now we've written stuff.
        end
      end
    end
  end
end
