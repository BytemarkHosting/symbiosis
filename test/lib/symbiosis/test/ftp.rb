#
#  Ruby class for working with the FTP settings of a domain
#

require 'symbiosis/test/symbiosisdomain'

  module Symbiosis
    module Test
      class Ftp < SymbiosisDomain

        #
        # Create the public directories so that we can login
        # via FTP.
        #
        def create
          super
          %w( public public/htdocs public/cgi-bin ).each do |d|
            create_dir File.join(self.directory, d)
          end
        end

        #
        # Set the FTP password for this domain
        #
        def password=( newpass )
          self.set_param("ftp-password", newpass)
        end

        #
        # Get the FTP password for this domain
        #
        def password
          c = self.get_param("ftp-password")
          raise "No FTP password set" unless c.is_a?(String)
          c.chomp
        end
      end
    end
  end
