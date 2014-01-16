require 'symbiosis/domain'

module Symbiosis

  class Domain

    #
    # Returns true if this domain has a chat server enabled.
    #
    def has_xmpp?
      get_param("xmpp",self.config_dir)
    end

  end

end
