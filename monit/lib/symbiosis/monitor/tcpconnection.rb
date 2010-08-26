require 'socket'
require 'timeout'

module Symbiosis
    module Monitor
      class TCPConnection

        attr_accessor :script, :host, :port, :timeout
        attr_reader   :transactions

        def initialize(host, port, script)
          @host = host
          @port = port
          @script = script
          @timeout = 5
          @transactions = []
          @newlines = [0, 10]
        end

        def preces
          return [] if @transactions.empty?
          @transactions.find_all{|t| "> " == t[0..1]}.collect{|t| t[2..-1]}
        end

        def responses
          return [] if @transactions.empty?
          @transactions.find_all{|t| "< " == t[0..1]}.collect{|t| t[2..-1]}
        end

        def do_check
          sock = nil
          @transactions = []
          begin
            Timeout.timeout(@timeout, Errno::ETIMEDOUT) { sock = TCPSocket.new(@host, @port) }
            @script.each do |line|
              unless line.nil?
                @transactions << "> "+line.inspect[1..-2]
                puts @transactions.last
                Timeout.timeout(@timeout, Errno::ETIMEDOUT) { sock.print line }
              else
                loop do
                  trans = ""
                  # read until we catch a null or newline char...
                  Timeout.timeout(@timeout, Errno::ETIMEDOUT) {trans << sock.read(1) } while !@newlines.include?(trans[-1])
                  # transform duff characters
                  @transactions << "< "+trans.inspect[1..-2] unless trans.empty?
                  puts @transactions.last
                  break if sock.eof?
                end
              end
            end
            Timeout.timeout(@timeout, Errno::ETIMEDOUT) { sock.close }
          rescue => err
            raise err
          ensure
            sock.close if sock.is_a?(Socket) and not sock.closed?
          end
        end
      end
    end
end

