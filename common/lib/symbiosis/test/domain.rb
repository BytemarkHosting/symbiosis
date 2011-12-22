#
#  Ruby class for creating a new domain
#

require 'symbiosis/utils'
require 'symbiosis/domain'
require 'tempfile'

module Symbiosis
 class Domain
    def directory
      File.join(Dir::tmpdir, "srv", @name)
    end
  end
end


