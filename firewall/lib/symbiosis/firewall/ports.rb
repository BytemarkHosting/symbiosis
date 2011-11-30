#
#
module Symbiosis
  class Firewall
    class Ports
      #
      # A hash of the service and port combinations
      #
      attr_reader :services

      #
      # Constructor.  Because this is a singleton class it is only
      # invoked once.
      #
      # We read the services-file and store the data from within it
      # into a hash for later lookups.
      #
      def initialize( filename = "/etc/services" )
        @services = Hash.new

        #
        #  Ensure the file exists
        #
        raise Errno::ENOENT, filename unless File.exists?(filename)

        #
        #  Read the file.
        #
        begin
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

      end


      #
      #  Find the TCP/UDP port of the named service.
      #
      def lookup( name )
        # numeric name is a cheat - we just return that port.
        return name.to_i if ( name =~ /^\d+$/ )

        # Lookup the port, if present.  This will default to nil
        @services[name.downcase]
      end

      #
      #  Is the name defined?
      #
      def defined?( name )
        lookup(name).nil?
      end

      private

      def add_service(srv, prt)
        srv = srv.downcase
        prt = prt.to_i
        unless @services.has_key?(srv)
          @services[srv] = prt
        else
          warn "#{srv} defined twice.  Ignoring definition for port #{prt}" unless prt == @services[srv]
        end
      end

    end

  end

end

