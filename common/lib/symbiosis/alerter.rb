
module Symbiosis

  #
  # This class is used for sending alerts/messages to the owner of a symbiosis host.
  #
  # Alerts will be sent by email in the typical case, or via mauve-alert where the
  # appropriate client is installed
  #
  class Alert

    #
    # The only public method of this class - raise an alert.
    #
    def self.raise_alert( subject, body )

       if has_mauve_alert?
          raise_mauve_alert( subject, body )
       else
          send_mail( "root", subject, body )
       end
    end

    private

    #
    # Check to see if we're a mauve-alert client installed
    #
    def self.has_mauve_alert?()
      ( File.exists?( "/etc/mauvealert/mauvesend.destination" ) &&
        File.exists?( "/usr/bin/mauvesend" ) )
    end

    #
    # Send the given message by email.
    #
    def self.send_mail( recipient, subject, body )
        # TODO
        throw "Not implemented"
    end

    #
    # Raise the given alert by mauve
    #
    def self.raise_mauve_alert( summary, detail )
        # TODO
        throw "Not implemented"
    end

  end

end


