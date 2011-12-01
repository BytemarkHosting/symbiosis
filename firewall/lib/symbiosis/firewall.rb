require 'symbiosis/firewall/rule'
require 'symbiosis/firewall/directory_ip_list'

#
# A meta-class which represents this firewall
#
module Symbiosis
  class Firewall

    attr_reader :incoming
    attr_reader :outgoing
    attr_reader :blacklist
    attr_reader :whitelist
    attr_reader :template
    attr_accessor :template_dir

    #
    #  Constructor
    #
    def initialize(dir="/etc/symbiosis/firewall")
      @base_dir = dir
      @template_dir = '/usr/share/symbiosis/firewall/rule.d/'
    end

    #
    # Exectute the command or die.
    #
    def xsys(cmd)
      if 0 == Process.uid
        exit $?.exitstatus unless Kernel.system(cmd)
      else
        warn "Not running #{cmd.inspect} -- not root!"
      end
    end


    #
    #  Is the firewall disabled?
    #
    def disabled?
      return File.exists?( File.join(@base_dir, "disabled" ) )
    end

    #
    # Run a self-test upon the firewall rules.  This merely needs to
    # test that an outgoing DNS lookup succeeds, and that an external
    # ping succeeds.
    #
    #  If the test fails it will call flush().
    #
    def test
      puts "'firewall --test' invoked.  TODO - Write code."
      0
    end

    def header
      <<EOF
#!/bin/bash
#
# 
########################################################################
#
# Firewall rules created by #{$0}
#
########################################################################
# 
# exit nicely.

set -e

EOF
    end

    #
    #  Flush/Remove all existing firewall rules.
    #
    def flush
      <<EOF
########################################################################
#
# flush all rules
#
########################################################################
/sbin/iptables -P INPUT ACCEPT
/sbin/iptables -P OUTPUT ACCEPT
/sbin/iptables -P FORWARD ACCEPT
/sbin/iptables -F
/sbin/ip6tables -P INPUT ACCEPT
/sbin/ip6tables -P OUTPUT ACCEPT
/sbin/ip6tables -P FORWARD ACCEPT
/sbin/ip6tables -F

EOF
    end

    def permit_lo
      <<EOF
########################################################################
#
# Permit access to loopback interfaces
#
#########################################################################
/sbin/iptables -I INPUT  -i lo -j ACCEPT
/sbin/iptables -I OUTPUT -o lo -j  ACCEPT
/sbin/ip6tables -I INPUT  -i lo -j ACCEPT
/sbin/ip6tables -I OUTPUT -o lo -j  ACCEPT

EOF
    end

    #
    #  This method is the key which ties all the distinct steps together.
    #
    #  It is responsible for :
    #
    #   1.  Writing out the static prefix to the firewall.
    #
    #   2.  Writing out the whitelist and blacklist parts.
    #
    #   3.  Writing out the individual rules.
    #
    #   4.  Closing and returning the name of that file.
    #
    def create_firewall
      #
      # This is an array of rules that will be written to the script
      #
      rules = []

      #
      # Make sure we permit loop-back interfaces
      #
      rules << permit_lo

      #
      # Process a whitelist, and then the blacklist
      #
      %w( whitelist blacklist ).each do |list_type|

        dir = File.join(@base_dir, "#{list_type}.d" )
        next unless File.directory?( dir )
        rules << "#"*72
        rules << "#"
        rules << "# #{list_type} from #{dir}"
        rules << "#"
        rules << "#"*72

        #
        #  Now write out our whitelist - which comes first.
        #
        list = DirectoryIPList.new( dir )
        rules += list.__send__(list_type)
      end

      %w( incoming outgoing ).each do |direction|
        #
        #  Finally we have to write out our rules.
        #
        dir = File.join(@base_dir, "#{direction}.d" )
        next unless File.directory?( dir )

        rules << "#"*72
        rules << "#"
        rules << "# #{direction} rules from #{dir}"
        rules << "#"
        rules << "#"*72

        read_rules( dir ).each do |name,addresses|
          #
          # Add a dummy address of nil if there are no addresses in the list
          #
          addresses << nil if addresses.empty?
          addresses.each do |address|
            begin
              #
              # Create a new rule
              #
              rule = Rule.new( name )
              rule.direction = direction
              rule.address = address unless address.nil?

              #
              # Add rule to list
              #
              rules << rule
            rescue ArgumentError => err
              #
              # Catch any error and display neatly.
              #
              msg = "Ignoring #{direction} rule #{name} #{address.nil? ? "" : "to #{address.inspect} "}because #{err.to_s}"
              warn msg
              rules << "# #{msg}"
            end
          end
        end
      end

      #
      # Finally add a run-parts rule for local.d
      #
      dir = File.join(@base_dir, "local.d" )
      if File.directory?( dir )
        rules << "#"*72
        rules << "#"
        rules << "# Run rules from #{dir} using run-parts"
        rules << "#"
        rules << "#"*72
        rules << "run-parts #{dir}"
      end

      output = rules.collect do |rule|
        begin
          #
          # Set the template dir.
          #
          rule.template_dir = @template_dir if rule.is_a?(Firewall::Rule)
          rule.to_s
        rescue ArgumentError => err
           #
           # Catch any error and display neatly.  Again.
           #
           msg = "Ignoring #{rule.direction} rule #{rule.name} #{rule.address.nil? ? "" : "to #{rule.address} "}because #{err.to_s}"
           warn msg
           "# #{msg}"
        end
      end

      return output.join("\n")
    end


    #
    # Here be dragons.
    #
    private

    #
    #  Read from an incoming/outgoing directory and collate the results.
    #
    # TODO:  Rethink this - as here we only read the names, and we should
    #        also take account of the ACL which might be inside the file.
    #
    def read_rules( directory )
      #
      # Results is an array of arrays:
      #
      #  [
      #    [port/template1, [ipaddress1, ipaddress2]],
      #    [port/template2, [ipaddress3, ipaddress4]],
      #  ]
      #
      # and so on.
      #
      results = Array.new

      return results unless File.directory?( directory )

      Dir.entries( directory ).reject{|f| f !~ /^([0-9]*)-(.*)$/}.sort.each do |entry|
        entry =~ /^([0-9]*)-(.*)$/
        template = $2
        #
        # File.readlines always returns an array, one element per line, even for dos-style files.
        #
        results << [template, File.readlines(File.join(directory,entry)).collect{|l| l.chomp}]
      end

      #
      #  Return the names.
      #
      results
    end

  end

end

