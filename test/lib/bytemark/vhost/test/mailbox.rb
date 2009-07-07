
#
#  Ruby class for working with the mailbox settings of a domain
#

require 'bytemark/vhost/test/vhostdomain'
require 'fileutils'

module Bytemark
  module Vhost
    module Test
      class Mailbox  

        attr_reader :user, :domain

        def initialize(user, domain)
          raise ArgumentError, "user must be a string" unless user.is_a?(String)
          @user = user

          raise ArgumentError, "domain must be a string" unless domain.is_a?(String)
          @domain = domain
        end

        def username
          [@user, @domain].join("@")
        end

        def directory
          "/srv/#{@domain}/mailboxes/#{@user}"
        end

        def create
          Bytemark::Vhost::Test.mkdir(self.directory)
        end

        def destroy
          FileUtils.rm_rf(self.directory)
        end

        def exists?
          File.exists?(self.directory)
        end

        def password=(pw)
          Bytemark::Vhost::Test.set_param("password", pw, self.directory)
        end

        def password
          Bytemark::Vhost::Test.get_param("password", self.directory).chomp
        end

        def forward=(f)
          Bytemark::Vhost::Test.set_param("forward",f, self.directory)
        end
        
        def forward
          Bytemark::Vhost::Test.get_param("forward", self.directory)
        end
      end
    end
  end
end


