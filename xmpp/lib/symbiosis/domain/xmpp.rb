require 'symbiosis/domain'
require 'symbiosis/domain/ssl'

module Symbiosis

  class Domain

    #
    # Returns true if this domain should have its chat server enabled.
    #
    def has_xmpp?
      value = get_param("xmpp",self.config_dir)

      (!value.nil? or value != false)
    end

  end

end
