#!/usr/bin/ruby
#
#

services = Hash.new{|h,k| h[k] = Hash.new{|i,l| i[l] = Array.new}}

action = ARGV.shift
action = "create" if action.nil?

output_dir = ARGV.shift
output_dir = "rule.d" if output_dir.nil?

services_file = ARGV.shift
services_file = "services" if services_file.nil?


File.open(services_file) do |fh|
  while line = fh.gets do
    if line =~ /^([\w-]+)\s+(\d+)\/(tcp|udp)\s*/
      services[$1][$2] << $3 unless services[$1][$2].include?($3)
    end
  end
end

services.each do |service, ports|
  [ "incoming", "outgoing" ].each do |direction|
    var = "$"+("incoming" == direction ? "SRC" : "DEST")
    fn = File.join(output_dir,"#{service}.#{direction}")
    skip = false

    # check to see if the file exists, and if so, see if it is auto-generated
    # (in which case we can overwrite it).
    File.open(fn, 'r') do |fh|
      unless fh.gets == "# AUTOMATICALLY GENERATED! Do not edit.\n"
        puts "Manually created file exists: rule.d/#{service}.#{direction}"
        skip = true
      end
    end if File.exists?(fn)

    next if skip

    if action == "clean"
      File.unlink(fn) if File.exists?(fn)
    else
      File.open(fn,"w+") do |fh|
        fh.puts "# AUTOMATICALLY GENERATED! Do not edit.\n#\n# Allow #{direction} connections for #{service}\n#\n"
        ports.each do |port, protos|
          protos.each do |proto|
            fh.puts ["/sbin/iptables",
                     "--append",
                    ("incoming" == direction ? "INPUT" : "OUTPUT"),
                    "--protocol",
                    proto,
                    "$DEV",
                    "--destination-port",
                    port,
                    ("incoming" == direction ? "$SRC" : "$DEST"),
                    "--jump ACCEPT"].join(" ")
          end
        end
        fh.puts ""
      end
    end
  end
end


