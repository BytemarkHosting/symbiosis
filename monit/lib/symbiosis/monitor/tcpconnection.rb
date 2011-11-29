require 'socket'
require 'openssl'
require 'timeout'

module Symbiosis
    module Monitor
      class TCPConnection

        attr_accessor :script, :host, :port, :timeout
        attr_reader   :transactions

        def initialize(host, port, script, ssl = false)
          @host = host
          @port = port
          @script = script
          @timeout = 5
          @transactions = []
          @ssl = ssl
        end

        def versicles
          return [] if @transactions.empty?
          @transactions.find_all{|t| "> " == t[0..1]}.collect{|t| t[2..-1]}
        end

        def responses
          return [] if @transactions.empty?
          @transactions.find_all{|t| "< " == t[0..1]}.collect{|t| t[2..-1]}
        end

        def connect
          sock = TCPSocket.new(@host, @port)
          if @ssl
            ssl_sock = OpenSSL::SSL::SSLSocket.new(
              sock,
              OpenSSL::SSL::SSLContext.new("SSLv3_client")
            )
            ssl_sock.sync_close = true
            ssl_sock.connect
            return ssl_sock
          else
            return sock
          end
        end

        def do_check
          sock = nil
          @transactions = []
          begin
            Timeout.timeout(@timeout, Errno::ETIMEDOUT) do
              sock = self.connect
              @script.each do |line|
                if line.is_a?(String)
                  @transactions << "> "+line.chomp.inspect[1..-2]
                  puts @transactions.last
                  sock.print line
                else
                  loop do
                    trans = sock.gets.chomp
                    # transform duff characters
                    @transactions << "< "+trans.inspect[1..-2]
                    puts @transactions.last
                    break if line.nil? or (line.is_a?(Regexp) and trans =~ line)
                  end
                end
              end
              sock.close
            end
          rescue => err
            raise err
          ensure
            sock.close if sock.is_a?(Socket) and not sock.closed?
          end
        end
      end
    end
end

