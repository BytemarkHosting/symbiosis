require 'eventmachine'
require 'em/protocols/line_protocol'
require 'symbiosis/domains'
require 'symbiosis/domain/mailbox'
require 'symbiosis/host'
require 'syslog'
require 'json'

module Symbiosis
  module Email
    class DictHandler < EM::Connection

      def self.prefix=(p)
        @@prefix = p
      end

      def self.syslog=(s)
        @@syslog = s
      end
 
      include EventMachine::Protocols::LineProtocol

      def receive_line(l)
        case l
          # DICT_PROTOCOL_CMD_HELLO = 'H',
          when /^H/
            do_hello(l)
          # DICT_PROTOCOL_CMD_LOOKUP = 'L', /* <key> */
          when /^L/
            ans = do_lookup(l)
            send_data ans
            close_connection(true)

          # DICT_PROTOCOL_CMD_ITERATE = 'I', /* <flags> <path> */
          # DICT_PROTOCOL_CMD_BEGIN = 'B', /* <id> */
          # DICT_PROTOCOL_CMD_COMMIT = 'C', /* <id> */
          # DICT_PROTOCOL_CMD_COMMIT_ASYNC = 'D', /* <id> */
          # DICT_PROTOCOL_CMD_ROLLBACK = 'R', /* <id> */
          # DICT_PROTOCOL_CMD_SET = 'S', /* <id> <key> <value> */
          # DICT_PROTOCOL_CMD_UNSET = 'U', /* <id> <key> */
          # DICT_PROTOCOL_CMD_APPEND = 'P', /* <id> <key> <value> */
          # DICT_PROTOCOL_CMD_ATOMIC_INC = 'A' /* <id> <key> <diff> */
          else
            send_data "F\n"
        
            # fail?
        end
      rescue StandardError => err
        send_data "F\n"
        syslog.warning "Caught #{err.to_s}"
        close_connection(true)
      end

      def syslog
        @@syslog
      end

      def prefix
        @@prefix
      end

      def do_hello(l)
        # log hello
      end

      def do_lookup(l)
        (namespace, type, username) = l[1..-1].split('/',3)

        #
        # Append our local hostname if none has been given.
        #
        unless username =~ /@/
          username = username +  "@" + Symbiosis::Host.fqdn.to_s
        end

        mailbox = Symbiosis::Domains.find_mailbox(username, prefix)

        if mailbox.nil?
          syslog.info "Non-existent mailbox #{username.inspect}"
          return "N\n"
        end

        res = {
          'user' => username,
          'home' => mailbox.directory,
          'uid' =>  mailbox.uid,
          'gid' =>  mailbox.gid,
          'mail' => "maildir:#{mailbox.directory}/Maildir",
          'sieve' => "file:#{mailbox.directory}/#{mailbox.dot}sieve",
          'sieve_dir' => "file:#{mailbox.directory}/#{mailbox.dot}sieve.d"
        }

        unless mailbox.quota.nil? or 0 == mailbox.quota
          res['quota_rule'] = "*:bytes=#{mailbox.quota}"
        end

        # Ugh
        begin
          #
          # Make sure our mailbox quota is correct.
          #
          mailbox.rebuild_maildirsize
        rescue StandardError => err
          syslog.warning "Caught #{err.to_s} when trying to rebuild Maildir/maildirsize file for #{username}."
        end

        if "passdb" == type
          # add userdb_ to each key in res
          passdb_res = {}
          res.collect{|k,v| passdb_res["userdb_#{k}"] = v}

          if mailbox.password        
            real_password = mailbox.password
            if real_password =~ /^(\{(?:crypt|CRYPT)\})?(\$(?:1|2a|5|6)\$[a-zA-Z0-9.\/]{1,16}\$[a-zA-Z0-9\.\/]+)$/
              password = real_password
            else
              password = mailbox.domain.crypt_password(real_password)
            end

            passdb_res["password"] = password 
          end
            
          res = passdb_res
        end

        return "O"+JSON.dump(res)+"\n"

      end

    end
  end
end
