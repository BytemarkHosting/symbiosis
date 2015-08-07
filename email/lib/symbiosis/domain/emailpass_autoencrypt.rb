require 'symbiosis/domain'
require 'symbiosis/domain/ssl'

module Symbiosis

  class Domain

    #
    # Returns true if this domain has email password encryption enabled.
    #
    def should_encrypt_mailbox_passwords?
      if get_param("mailbox-dont-encrypt-passwords",self.config_dir)
        false
      else
        true
      end
    end

  end

end
