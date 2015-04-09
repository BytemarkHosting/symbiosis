

module Symbiosis
  module Email
    class DictHandler < EM::Protocols::LineAndText


      def receive_line(l)
        case l
          # DICT_PROTOCOL_CMD_HELLO = 'H',
          when /^H/
            do_hello(l)
          # DICT_PROTOCOL_CMD_LOOKUP = 'L', /* <key> */
          when /^L/
            do_lookup(l)

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
            # fail?
        end
      end

      def do_hello(l)
        # log hello
      end

      def do_lookup(l)
        (namespace, type, username) = l[1..-1].split ('/',3)

        mailbox = Symbiosis::Domains.find_mailbox(username, prefix)

        if mailbox.nil?
          syslog.info "Non-existent mailbox #{username.inspect} from #{ip} for #{service} service"
          syslog.err  "#{service} login failure from IP: #{ip} username: #{username.inspect}"
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
        end

        return "O"+JSON.dump(res)+"\n"

      end
    end
  end
end
