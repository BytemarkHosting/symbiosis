require 'symbiosis/monitor/service/systemd'
require 'symbiosis/monitor/service/sysv'

module Symbiosis
  module Monitor
    # Abstraction for getting a Service of the correct type for your init system
    class Service
      # Get a service object to talk to.
      # description is a hash of params.
      #  :unit_name - the name of the Systemd unit, minus the ".service"
      #         e.g. apache2
      #  :init_script - the full path to the init script
      #         e.g. /etc/init.d/apache2
      #  :pid_file - the full path of the pid file written by the service
      #         e.g. /var/run/apache2.pid
      #
      #  services should absolutely respond to these messages:
      #  :start, :stop, :running?, :disable, :enable, :enabled?
      def self.from_description(description)
        return nil if description.nil?

        case init_system
        when :systemd
          Symbiosis::Monitor::SystemdService.new(description)
        when :sysv
          Symbiosis::Monitor::SysvService.new(description)
        else
          raise UnsupportedInitSystemError init_system.to_s
        end
      end

      # detect the init system in use on this machine
      # currently only systemd and sysvinit are supported
      def self.init_system
        Symbiosis::Monitor::SystemdService.systemd? ? :systemd : :sysv
      end
    end
  end
end

# vim: softtabstop=0 expandtab shiftwidth=2 smarttab:
