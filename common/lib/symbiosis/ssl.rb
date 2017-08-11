module Symbiosis
  class SSL
    PROVIDERS ||= []

    def self.call_hooks(domains_with_updates)
      return if domains_with_updates.empty?

      Dir.glob('/etc/symbiosis/ssl-hooks.d/*').each do |script|
        next unless File.executable?(script)
        IO.popen([script, 'live-update'], 'r+') do |io|
          io.puts domains_with_updates.join("\n")
          io.close_write # Close the pipe now we've written stuff.
        end
      end
    end
  end
end
