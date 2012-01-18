#
#  Ruby class for working with a HTTP domain.
#

module Symbiosis

  class Domain 

    def create_public_dir
      self.create
      %w( public/htdocs public/cgi-bin ).each do |d|
        create_dir (File.join(self.directory, d))
      end
    end

    # Create a stub index file.
    #
    def setup_http()
      create_public_dir
      File.open( "#{self.directory}/public/htdocs/index.html", "w" ) do |file|
       file.write( "<html><head><title>#{self.name}</title><body><h1>Test</h1></body.</html>\n" )
      end
    end

    #
    # Create a stub index file.
    #
    def create_php()
      create_public_dir
      File.open( "#{self.directory}/public/htdocs/index.php", "w" ) do |file|
        file.write( "<?php phpinfo(); ?>\n" )
      end
    end

    #
    # Create a stub CGI script
    #
    def create_cgi()
      create_public_dir
      File.open( "#{self.directory}/public/cgi-bin/test.cgi", "w" ) do |file|
        file.write( "#!/bin/bash\n" )
        file.write( "echo -e \"Content-type: text/plain\\n\\n\"\n" )
        file.write( "/usr/bin/uptime\n" )
      end
    end

    #
    # Change the permissions on our stub CGI-script to make it executable.
    #
    def setup_cgi()
      create_public_dir
      system( "chmod 755 #{self.directory}/public/cgi-bin/test.cgi" )
    end
  end
end


