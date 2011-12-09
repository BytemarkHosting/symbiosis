#
#  Ruby class for working with the mail settings of a domain
#

require 'symbiosis/test/symbiosisdomain'
require 'symbiosis/test/mailbox'
require 'fileutils'

  module Symbiosis
    module Test
      class Mail < SymbiosisDomain 

        def initialize
          super
          @mailboxes = []
        end

        def create
          super
          create_dir(File.join(self.directory, "mailboxes"))
        end

        def add_mailbox(user)
          mb = self.mailbox(user)
          return mb unless mb.nil?

          mb = Mailbox.new(user, self)
          mb.create

          @mailboxes << mb

          mb
        end

        def destroy_mailbox(user)
          mb = self.mailbox(user)
          raise "No such mailbox" if mb.nil?

          @mailboxes.delete(mb)
        end

        def mailbox(user)
          @mailboxes.find{ |mb| mb.username == user+"@"+@name }
        end
      end
    end
  end

