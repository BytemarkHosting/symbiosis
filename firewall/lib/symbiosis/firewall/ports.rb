module Symbiosis

  module Firewall

    #
    # This class is used to convert names to port numbers using the details
    # from /etc/services.
    #
    # This class only has class methods so that it is accessible globally.
    #
    class Ports

      class << self
        #
        # We read the services-file and store the data from within it
        # into a hash for later lookups.
        #
        # The hash has the form
        # 
        #  {
        #    name => port
        #  }
        #
        def load( filename = "/etc/services" )
          #
          #  Read the file.
          #
          File.open(filename).readlines().each do |line|
            #
            # service-names are alphanumeric - but also include "-" and "_".
            # Only interested in TCP or UDP services.
            #
            if ( line =~ /^([\w-]+)\s+(\d+)\/(?:tcp|udp)\s*([\w -]+)*/ )
              srv, port, other_names = $1,$2,$3
              add_service(srv, port)
              other_names.to_s.split(/\s+/).each{ |n| add_service(n, port) }
            end
          end

        end
  
        #
        # Just return the hash of services, in the form
        #
        #  {
        #   name => port,
        #  }
        #
        def services
          self.reset unless defined? @services
          @services
        end

        #
        # Empty the services hash, to force a reload.
        #
        def reset
          @services = Hash.new
        end

        #
        #  Find the TCP/UDP port of the named service.
        #
        #  If the name looks like a number, then we convert that to an integer,
        #  and return.  Otherwise the name is looked up in @services.  If no
        #  port is found, nil is returned.
        #
        def lookup( name )
          # numeric name is a cheat - we just return that port.
          return name.to_i if ( name =~ /^\d+$/ )

          self.load if self.empty?

          # Lookup the port, if present.  This will default to nil
          self.services[name.downcase]
        end

        #
        # Is the name defined in /etc/services?
        #
        def defined?( name )
          lookup(name).nil?
        end

        #
        # Have any services been defined?
        #
        def empty?
          self.services.empty?
        end

        private

        #
        # Add the service to our hash, if it hasn't been defined already.
        #
        def add_service(srv, prt)
          srv = srv.downcase
          prt = prt.to_i
          unless self.services.has_key?(srv)
            self.services[srv] = prt
          else
            unless prt == self.services[srv]
              warn "#{srv} defined twice.  Ignoring definition for port #{prt}" if $VERBOSE
            end
          end
        end

      end

    end

  end

end
