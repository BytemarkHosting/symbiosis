
#
#  Ruby class for working with the mailbox settings of a domain
#

require 'bytemark/vhost/test/vhostdomain'
require 'fileutils'

module Bytemark
  module Vhost
    module Test
      class Mailbox  

        attr_reader :user, :domain, :uncrypted_password

        def initialize(user, domain)
          raise ArgumentError, "user must be a string" unless user.is_a?(String)
          @user = user

          raise ArgumentError, "domain must be a vhostdomain #{domain.class.to_s}" unless domain.is_a?(Bytemark::Vhost::Test::VhostDomain)
          @domain = domain

          @uncrypted_password = nil
        end

        def username
          [@user, @domain.name].join("@")
        end

        def directory
          File.join(@domain.directory, "mailboxes", @user)
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
          @uncrypted_password = pw
          Bytemark::Vhost::Test.set_param("password", pw, self.directory)
        end

        def crypt_password
          salt = ["a".."z","A".."Z","0".."9",".","/"].collect{|r| r.to_a}.flatten.values_at(rand(64), rand(64)).join
          pw = "{CRYPT}"+@uncrypted_password.crypt(salt)
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


