require 'eventmachine'
require 'em/protocols/line_protocol'
require 'symbiosis/domains'
require 'symbiosis/domain/mailbox'
require 'syslog'
require 'cracklib'

module Symbiosis
  module Email
    class PoppassHandler < EM::Connection

      def initialize(fail_timeout = 3)
        @fail_timeout = fail_timeout
      end

      def self.prefix=(p)
        @@prefix = p
      end

      def self.syslog=(s)
        @@syslog = s
      end
 
      include EventMachine::Protocols::LineProtocol
    
#    C: <open connection to port 106>
#    S: 200 poppassd (version 1.1) ready.
#    C: USER fred
#    S: 300 send password
#    C: PASS stupid
#    S: 200 Hello, fred.
#    C: NEWPASS still-stupid
#    S: 200 Password changed for fred
#    C: QUIT
#    S: Goodby.
#
#    C: <open connection to port 106>
#    S: 200 poppassd (version 1.1) ready.
#    C: USER fred
#    S: 300 send password
#    C: PASS stupid
#    S: 500 Incorrect login.
#    C: QUIT
#    S: Goodby.

      def post_init
        send_data "200 Hello, who are you?\r\n"
        @user = @mailbox = nil
        @authorised = false
      end

      def receive_line(l)
        case l
          when /^USER (.+)$/i
            @username = $1
            @authorised = false
            send_data "300 Please send your current password\r\n"
            
          when /^PASS (.+)$/i
            @authorised = false
            ans = do_authorise($1)
            send_data ans

          when /^NEWPASS (.+)$/i
            ans = do_change_password($1)
            send_data ans

          when /^QUIT/i
            send_data "200 ta-ra\r\n"
            close_connection(true)

          else
            send_data "500 I don't understand what you're saying.\r\n"
        
        end
      rescue StandardError => err
        send_data "500 Something bad has happened.  Sorry!\r\n"
        syslog.err "Caught #{err.to_s}"
        close_connection(true)
      end

      def syslog
        @@syslog
      end

      def prefix
        @@prefix
      end

      def do_authorise(passwd)

        unless @username
          return "400 Please send your username first!\r\n"
        end

        @mailbox = Symbiosis::Domains.find_mailbox(@username, self.prefix)

        if @mailbox.nil?
          syslog.notice "Non-existent mailbox #{@username.inspect}"
          sleep @fail_timeout
          return "500 Incorrect login\r\n"
        end

        begin
          @authorised = @mailbox.login(passwd)
        rescue ArgumentError => err
          syslog.notice "Unable to login to mailbox #{@mailbox.username} because #{err.to_s}"
          sleep @fail_timeout
          return "500 Incorrect login\r\n"
        end

        unless @authorised
          syslog.notice "Incorrect password given for mailbox #{@mailbox.username}"
          sleep @fail_timeout
          return "500 Incorrect login\r\n"
        end

        return "200 Nice to see you again, #{@username}\r\n"
      end

      def do_change_password(passwd)
        unless @authorised
          return "400 Please login before trying to change your password\r\n"
        end

        c = CrackLib::Fascist(passwd)

        unless c.ok?
          syslog.notice "Password change failed for user #{@mailbox.username} -- #{c.reason}"
          return "400 Sorry, that password is too weak -- #{c.reason}\r\n"
        end

        begin
          @mailbox.password = passwd
        rescue StandardError => err
          syslog.err "Password change failed for user #{@mailbox.username} because #{err.to_s}"
          return "400 Sorry, it was not possible to change your password due to a system error.\r\n"
        end

        syslog.info "Password changed for user #{@mailbox.username}"
        return "200 Password changed\r\n"
      end
    end
  end
end

