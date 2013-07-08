#!/usr/bin/ruby
#
# This script is designed to generate per-domain statistics for each
# domain hosted upon the current system.
#
# It does this in a multi-step process:
#
#
#   1.  Split /var/log/apache2/access.log into a number of files,
#      one for each domain, in a temporary directory
#
#   2.  For each split file which has been generated append the contents
#      to /srv/$domain/logs/access.log - working out the domain name by
#      examination of the file name.
#
#   3.  Once each access.log file has been placed into the logs/ directory
#      it is resolved into hostnames, via logresolve, and stored at
#      access.log.resolved
#
#   4.  If the htdocs/ directory is non-empty, and the file /config/no-stats
#      is missing then webalizer is run against the resolved file.
#
#   5.  Finally the access.log file is removed, the access.log.resolved
#      file is renamed to be access.log.$date
#
#   6.  At this point "old" logs are removed.
#
#   7.  Done.
#
# Steve
# --
#


require 'date'
require 'fileutils'
require 'getoptlong'
require 'tmpdir'



#
#  Given a logfile split it in a temporary directory, into one file
# per domain.
#
def split_access_log( filename )

  #
  #  Create a temporary directory
  #
  dir = Dir.mktmpdir

  #
  #  Now split the logfile in this directory
  #
  system( "cd #{dir} && split-logfile < #{filename}" )

  #
  #  Return the directory name
  #
  return( dir );

end


#
#  Given the name of a logfile, and the directory it appears in
# try to match that against a domain
#
def add_to_domain(dir, file )

  log = "#{dir}/#{file}"

  #
  #  Find the domain name from the file name
  #
  domain = file.gsub(/\.log$/i, '' );

  dest = ""
  ret = ""

  #
  #  If the domain exists then we're golden.
  #
  if ( File.directory?( "/srv/#{domain}" ) )
    dest = "/srv/#{domain}/public/logs"
    ret = domain
  end

  #
  #  Now try again without the www. prefix
  #
  domain = domain.gsub( /^www\./i, '')
  if ( File.directory?( "/srv/#{domain}" ) )
    dest = "/srv/#{domain}/public/logs"
    ret = domain
  end


  #
  #  OK at this point we either have an empty destination, or
  # a valid one.
  #
  #  If we have a destination make the logs directory, if missing
  # and append the file to it.
  #
  if ( dest.length > 0 )
    if ( !File.directory?( dest ) )
      FileUtils.mkdir_p( dest )
    end
    system( "cat #{log} >> #{dest}/access.log" )
  end

  return ret;
end


#
#  Does the domain have content?
#
def has_content?( domain )

  count = 0

  #
  #  If the public/htdocs/ folder doesn't exist the domain is empty.
  #
  return false if ( !File.directory?( "/srv/#{domain}/public/htdocs" ) )

  #
  #  Otherwise count the non-dotfile entries
  #
  Dir.foreach("/srv/#{domain}/public/htdocs" ) do |entry|
    next if ( entry =~ /^\./ )
    count += 1;
  end

  #
  #  Did we find something?
  #
  return ( count != 0 )
end


#
#  Are statistics generated for the domain?
#
def stats_disabled_for_domain?( domain )
  return( File.exists?( "/srv/#{domain}/config/no-stats" ) )
end



###
#
#  Start of code
##
####################################


#
# Options parsing
#
opts = GetoptLong.new(
                        [ "--verbose",    "-v", GetoptLong::NO_ARGUMENT ]
                      )

opts.each do |opt, arg|
  case opt
  when "--verbose"
    $VERBOSE=1
  end
end

#
#  First of all exit if we don't have a logfile.
#
if ( !File.exists?( "/var/log/apache2/access.log" ) )
  puts( "Missing apache logfile: /var/log/apache2/access.log" ) if $VERBOSE
  exit( 0 );
end

#
#  Split the existing logfile into a number of files, one for each
# virtual host which has been accessed within the past day
#
dir = split_access_log( "/var/log/apache2/access.log" );


#
#  Process the directory of split logfiles
#
domains = Hash.new()

Dir.foreach(dir) do |entry|

  #
  #  If the logfile contains a name.
  #
  next if ( entry =~ /^\./ )

  #
  #  If we can find the domain name for this log then
  # we'll append it.
  #
  domain = add_to_domain( dir, entry );

  domains[domain] = 1 if ( domain.length > 0 )
end


#
#  OK for each domain we've added logfile entries to
#
#
domains.each_key do |domain|

  puts "Processing log for domain #{domain}" if $VERBOSE

  #
  #  Resolve the logfile, regardless of whether we're going to make
  # statistics or not.
  #
  system( "logresolve < /srv/#{domain}/public/logs/access.log > /srv/#{domain}/public/logs/access.log.resolved" )


  #
  #  Now if we've got content.
  #
  if ( has_content?(domain) )

    #
    #  Does this domain have stats disabled?
    #
    if ( stats_disabled_for_domain?( domain ) )

      puts "\tStats disabled for domain: #{domain}" if $VERBOSE

    else

      #
      #  Create the output directory
      #
      if ( !File.directory?( "/srv/#{domain}/public/htdocs/stats" ) )
        FileUtils.mkdir_p(  "/srv/#{domain}/public/htdocs/stats" );
      end

      #
      #  If the webalizer file isn't present create it
      #
      if ( !File.exists?( "/srv/#{domain}/public/htdocs/stats/webalizer.conf" ) )

        puts "\tCreating webalizer configuration file" if $VERBOSE

        File.open( "/srv/#{domain}/public/htdocs/stats/webalizer.conf", "w" ) do |f|
          f.write <<"EOF"

OutputDir       /srv/#{domain}/public/htdocs/stats/
Incremental     yes
ReportTitle     Usage Statistics for
HostName        #{domain}
HideSite        #{domain}
HideReferrer    #{domain}/
HideReferrer    Direct Request
HideURL         *.gif
HideURL         *.GIF
HideURL         *.jpg
HideURL         *.JPG
HideURL         *.ra
GroupURL        /cgi-bin/*
MangleAgents    4
EOF
                                 end

        puts "\tRunning webalizer" if $VERBOSE


        #
        #  Now run it
        #
        system( "cd /srv/#{domain}/public/htdocs/stats/ && webalizer -q /srv/#{domain}/public/logs/access.log.resolved" );
      end
    end

  else

      puts "\tDomain has no content: #{domain}"

  end

  #
  #  Finally for each /srv/*/public/logs/access.log
  #
  #  1.  Rename to access.$date
  #
  #  2.  Remove "old" entries.
  #
  #
  if ( File.exists?( "/srv/#{domain}/public/logs/access.log" ) )
    File.unlink( "/srv/#{domain}/public/logs/access.log" )
  end

  #
  #  Rename
  #
  date = Date.today.to_s
  File.rename( "/srv/#{domain}/public/logs/access.log.resolved",
               "/srv/#{domain}/public/logs/access.log.#{date}" )


  #
  #  Now we need to remove the old files in the directory.
  #
  Dir.new("/srv/#{domain}/public/logs").each do |name|
    if File.file?(name)
      if File.mtime(name) < Time.now - (60 * 60 * 24 * 10)
        puts "\tCleaning up old logfile: #{name}" if $VERBOSE
        File.unlink(name)
      end
    end
  end
end

#
#  Finally cleanup the temporary directory
#
system( "rm -rf #{dir}" )
