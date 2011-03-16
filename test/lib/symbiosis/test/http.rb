#
#  Ruby class for working with a HTTP domain.
#

require 'symbiosis/test/symbiosisdomain'

  module Symbiosis
    module Test
      class Http < SymbiosisDomain

        def create
          super
          %w( public public/htdocs public/cgi-bin ).each do |d|
            create_dir File.join(self.directory, d)
          end
        end

        # Create a stub index file.
        #
        def setup_http()
          file = File.open( "/srv/#{self.name}/public/htdocs/index.html", "w" )
          file.write( "<html><head><title>#{self.name}</title><body><h1>Test</h1></body.</html>\n" )
          file.close()
        end

        #
        # Create a stub index file.
        #
        def create_php()
          file = File.open( "/srv/#{self.name}/public/htdocs/index.php", "w" )
          file.write( "<?php phpinfo(); ?>\n" )
          file.close()
        end

        #
        # Create a stub CGI script
        #
        def create_cgi()
          file = File.open( "/srv/#{self.name}/public/cgi-bin/test.cgi", "w" )
          file.write( "#!/bin/bash\n" )
          file.write( "echo -e \"Content-type: text/plain\\n\\n\"\n" )
          file.write( "/usr/bin/uptime\n" )
          file.close()
        end

        #
        # Change the permissions on our stub CGI-script to make it executable.
        #
        def setup_cgi()
          system( "chmod 755 /srv/#{self.name}/public/cgi-bin/test.cgi" )
        end

      end
    end
  end


