require "fcntl"
require "fileutils"

module Symbiosis

  #
  # This module has a number of useful methods that are used everywhere.
  #
  module Utils


    #
    # Many of our utility scripts have integrated documentation at their
    # head.
    #
    # This method will show the manual to the caller.
    #
    def show_manual( filename )
      show_help_or_manual( filename, false )
    end

    #
    # Many of our utility scripts have integrated documentation at their
    # head.
    #
    # This method will show brief usage-information to the caller.
    #
    def show_help( filename )
      show_help_or_manual( filename, true )
    end

    alias :show_usage :show_help

    #
    #  Show either the manual, or the brief usage text.
    #
    def show_help_or_manual( filename, help )

      #
      # Open the file, stripping the shebang line
      #
      lines = File.open(filename){|fh| fh.readlines}[1..-1]

      found_synopsis = false

      lines.each do |line|

        line.chomp!
        break if line.empty?

        if help and !found_synopsis
          found_synopsis = (line =~ /^#\s+SYNOPSIS\s*$/)
          next
        end

        puts line[2..-1].to_s
        break if help and found_synopsis and line =~ /^#\s*$/
      end

    end


    # 
    # This function uses the FileUtils mkdir_p command to make a directory.
    # It adds the extra options of :uid and :gid to allow these to be set in
    # one fell swoop.
    #
    # This has been written to avoid the TOCTTOU race conditions between
    # creating a directory, and chowning it, to make sure that we don't
    # accidentally chown a file on the end of a symlink
    #
    # It returns the name of the directory created.
    #
    def mkdir_p(dir, options = {})
      # Switch on verbosity..
      options[:verbose] = true if $DEBUG

      # Find the first directory that exists, and the first non-existent one.
      parent = File.expand_path(dir)

      begin
        #
        # Check the parent.
        #
        lstat_parent = File.lstat(parent)
      rescue Errno::ENOENT
        lstat_parent = nil
      end

      return parent if !lstat_parent.nil? and lstat_parent.directory?

      #
      # Awooga, something already in the way.
      #
      raise Errno::EEXIST, parent unless lstat_parent.nil?

      #
      # Break down the directory until we find one that exists.
      #
      stack = []
      while !File.exist?(parent)
        stack.unshift parent
        parent = File.dirname(parent)
      end

      # 
      # Then set the options such that the uid/gid of the parent dir can be
      # propagated, but only if we're root.
      #
      if (options[:uid].nil? or options[:gid].nil?) and 0 == Process.euid
        parent_s = File.stat(parent)
        options[:gid] = parent_s.gid if options[:gid].nil?
        options[:uid] = parent_s.uid if options[:uid].nil?
      end

      #
      # Set up a sensible mode
      #
      unless options[:mode].is_a?(Integer)
        options[:mode] = (0777 - File.umask)
      end

      #
      # Create our stack of directories in real life.
      #
      stack.each do |sdir|
        begin
          #
          # If a symlink (or anything else) is in the way, an EEXIST exception
          # is raised.
          #
          Dir.mkdir(sdir, options[:mode])
        rescue Errno::EEXIST => err
          #
          # If there is a directory in our way, skip and move on.  This could
          # be a TOCTTOU problem.
          #
          next if File.directory?(sdir)

          #
          # Otherwise barf.
          #
          raise err
        end

        #
        # Use lchown to prevent accidentally chowning the target of a symlink,
        # instead chowning the symlink itself.  This mitigates a TOCTTOU race
        # condition where the attacker replaces our new directory with a
        # symlink to a file he can't read, only to have us chown it.
        #
        File.lchown(options[:uid], options[:gid], sdir)
      end

      return dir
    end

    # 
    # This function generates a string of random numbers and letters from the
    # sequence A-Z, a-z, 0-9 minus 0, O, o, 1, I, i, l.
    #
    def random_string( len = 10 )
      raise ArgumentError, "length must be an integer" unless len.is_a?(Integer)

      randchars = "23456789abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"

      name=""

      len.times { name << randchars[rand(randchars.length)] }

      name
    end

    #
    # Allow arbitrary parameters in parent_dir to be retrieved.
    #
    # * nil is returned if the file does not exist, or is not readable
    # * true is returned if the file exists, but is of zero length, or if the file contains the word "yes" or "true"
    # * false is returned if the file contains the word "false" or "no"
    # * otherwise the files contents are returned as a string.
    #
    def get_param(setting, parent_dir, opts = {})
      fn = File.join(parent_dir, setting)

      #
      # Return false unless we can read the file
      #
      return nil unless File.exist?(fn) and File.readable?(fn)

      #
      # Read the file.
      #
      contents = safe_open(fn, File::RDONLY, opts){|fh| fh.read}.to_s
      
      #
      # Return true if the file was empty, or the contents are "true" or "yes"
      #
      return true if contents.empty? or contents =~ /\A\s*(true|yes)\s*\Z/i

      #
      # Return false if the file is set to "false" or "no"
      #
      return false if contents =~ /\A\s*(false|no)\s*\Z/i

      #
      # Otherwise return the contents
      #
      return contents
    end

    #
    # This returns the first setting of a parameter in a stack of directories.
    #
    # Returns the first non-
    #
    def get_param_with_dir_stack(setting, dir_stack, opts = {})
      var = nil

      [dir_stack].flatten.each do |dir|
        var = get_param(setting, dir, opts)
        break unless var.nil?
      end

      var
    end

    #
    # Records a parameter.
    #
    # * true is stored as an empty file
    # * false or nil causes the file to be removed, if it exists.
    # * Anything else is converted to a string and stored.
    #
    # If a file is created, or written to, then the permissions are set such
    # that the file is owned by the same owner/group as the parent_dir, and
    # readable by everyone, but writable only by the owner (0644).
    #
    # Directories owned by system users/groups will not be written to.
    #
    def set_param(setting, value, parent_dir, opts = {})
      fn = File.join(parent_dir, setting)

      #
      # Make sure the directory exists first
      #
      raise "Config directory does not exist." unless File.exist?(parent_dir)

      #
      # Check the parent directory.
      #
      parent_dir_stat = File.stat(parent_dir)

      #
      # Refuse to write to directories owned by UIDs < 1000.
      #
      raise ArgumentError, "Parent directory #{parent_dir} is owned by a system user." unless parent_dir_stat.uid >= 1000


      if false == value or value.nil?
        #
        # This doesn't follow symlinks.
        #
        File.unlink(fn) if File.exist?(fn)

      else
        #
        # Merge in our options
        #
        opts = opts.merge({:mode => 0644, :uid => parent_dir_stat.uid, :gid => parent_dir_stat.gid})

        #
        # Create the file
        #
        safe_open(fn, File::WRONLY|File::CREAT, opts) do |fh|
          #
          # We're good to go.
          #
          fh.truncate(0)
          
          #
          # Record the value
          #
          fh.write(value.to_s) unless true == value
        end

      end

      #
      # Return the value we were originally given
      #
      value
    end

    #
    # This method opens a file in a safe manner, avoiding symlink attacks and
    # TOCTTOU race conditions.
    #
    # The mode can be a string or an integer, but must not be "w" or "w+", or
    # have File::TRUNC set, to avoid truncating the file on opening.
    #
    # +opts+ is an options hash in which the uid, gid, and mode file bits can
    # be specified.
    # 
    # * :uid is the User ID, e.g. 1000.
    # * :gid is the Group ID, e.g. 1000.
    # * :mode is the permissions, e.g. 0644.
    #
    # By default mode is set using the current umask.  
    #
    def safe_open(file, mode = File::RDONLY, opts = {}, &block)
      #
      # Make sure the mode doesn't automatically truncate the file
      #
      if mode.is_a?(String)
        raise Errno::EPERM, "Bad mode string #{mode.inspect} for opening a file safely." if %w(w w+).include?(mode)

      elsif mode.is_a?(Integer)
        raise Errno::EPERM, "Bad mode string #{mode.inspect} for opening a file safely." if (File::TRUNC == (mode & File::TRUNC))

      else
        raise ArgumentError, "Bad mode #{mode.inspect}"

      end

      #
      # set some default options
      #
      opts = {:uid => nil, :gid => nil, :mode => (0666 - File.umask)}.merge(opts)

      #
      # Set up our filehandle object.
      #
      fh = nil

      begin  
        #
        # This will raise an error if we can't open the file
        #
        fh = File.open(file, mode, opts[:mode])

        #
        # Check to see if we've opened a symlink.
        #
        link_stat = fh.lstat
        file_stat = fh.stat
  
        if link_stat.symlink? and file_stat.uid != link_stat.uid
          #
          # uh-oh .. symlink pointing at a file owned by someone else?
          #
          raise Errno::EPERM, file
        end

        #
        # Check to see if the file is writable, is a file, and opened for
        # writing.  If so, we can set uid/gid/mode.
        #
        if ( link_stat.writable? and link_stat.file? and 
           ( File::WRONLY == (fh.fcntl(Fcntl::F_GETFL) & File::WRONLY) or 
             File::RDWR == (fh.fcntl(Fcntl::F_GETFL) & File::RDWR) ) )

          #
          # Change the uid/gid as needed.
          #
          if ((opts[:uid] and file_stat.uid != opts[:uid]) or 
              (opts[:gid] and file_stat.gid != opts[:gid]))
            #
            # Change the owner if not already correct
            #
            fh.chown(opts[:uid], opts[:gid])
          end

          if opts[:mode]
            #
            # Fix any permissions.
            #
            fh.chmod(opts[:mode])
          end

        end
      rescue ArgumentError, IOError, SystemCallError => err

        fh.close unless fh.nil? or fh.closed?
        raise err
      end

      if block_given?
        begin
          #
          # Yield the block, and then close the file.
          #
          yield fh
        ensure
          #
          # Close the file, if possible.
          #
          fh.close unless fh.nil? or fh.closed?
        end
      else
        #
        # Just return the file handle.
        #
        return fh
      end
      
    end

    #
    # If a numeric argument is given, it is rounded to the nearest whole
    # number, and returned as an Integer.
    #
    # If a string is given, the method attempts to parse it.  The quota can be
    # a decimal, followed optionally by a space, and optionally by a "prefix".
    # Prefixes it understands are:
    #
    #  * k, M, G, T, P as powers of 10
    #  * ki, Mi, Gi, Ti, Pi as powers of 2.
    # 
    # The answer is given as an Integer.
    #
    # An argument error is given if the string cannot be parsed, or the
    # argument is neither a Numeric or String object.
    #
    def parse_quota(quota)
      if quota.is_a?(Numeric)
        return quota.round.to_i
 
      elsif quota.is_a?(String) and quota =~ /^\s*([\d\.]+)\s*([bkMGTP]i?)?/

        n = $1.to_f
        m = case $2
          when "k"
           1e3
          when "M"
            1e6
          when "G"
            1e9
          when "T"
            1e12
          when "P"
            1e15
          when "ki"
            2**10
          when "Mi"
            2**20
          when "Gi"
            2**30
          when "Ti"
            2**40
          when "Pi"
            2**50
          else 1
        end

        return (n*m).round.to_i
      elsif quota.is_a?(String)
        raise ArgumentError, "Cannot parse quota #{quota.inspect}"
      else
        raise ArgumentError, "parse_quota requires either a String or Numeric argument"
      end
    end

    #
    # This function locks an open filehandle fh using flock.
    #
    # If the lock is unavailable it raises Errno::ENOLCK.
    #
    # N.B. This lock is realeased if the filehandle is closed, or if the file
    # itself is subsquently opened and closed.
    #
    def lock(fh)
      raise ArgumentError, "Expected a file handle not a #{fh.class}" unless fh.is_a?(File)
      raise ArgumentError, "File handle #{fh} is closed" if fh.closed?

#      flock_struct = [Fcntl::F_WRLCK, IO::SEEK_SET, 0, 0, 0])
#      fh.fcntl(Fcntl::F_SETLK, flock_struct.pack("s2L2i*"))

      if fh.flock(File::LOCK_EX | File::LOCK_NB)
        return 0
      else
        raise Errno::EAGAIN
      end

    rescue SystemCallError => err
      raise Errno::ENOLCK, "Unable to acquire lock -- #{err.to_s}"
    end

    #
    # This function removes any lock set by lock() on a filehandle, fh.
    #
    def unlock(fh)
      raise ArgumentError, "Expected a file handle not a #{fh.class}" unless fh.is_a?(File)
      raise ArgumentError, "File handle #{fh} is closed" if fh.closed?

#      flock_struct = [Fcntl::F_UNLCK, IO::SEEK_SET, 0, 0, 0])
#      fh.fcntl(Fcntl::F_SETLK, flock_struct.pack("s2L2i*"))

      if fh.flock(File::LOCK_UN | File::LOCK_NB)
        return 0
      else
        raise Errno::EAGAIN
      end

    rescue SystemCallError => err
      raise Errno::ENOLCK, "Unable to release lock -- #{err.to_s}"
    end

    def guess_init_system
      if File.exist?('/run/systemd/system')
        puts "systemd detected" if $VERBOSE
        return :systemd
      elsif system("which initctl > /dev/null 2>&1")
        if `initctl version` =~ /upstart/
          puts "upstart detected" if $VERBOSE
          return :upstart
        else
          puts "initctl shim detected" if $VERBOSE
          return :upstart # if there's an upstart shim we might still be able to use it
        end
      else
        puts "nothing detected - assuming init scripts will work" if $VERBOSE
        return :sysv
      end

    end

    def service_running?(service)
      case guess_init_system
      when :systemd
        system("systemctl status #{service}")
      when :upstart
        system("initctl start #{serice}")
      when :sysv
        system("/etc/init.d/#{service} start")
      end
    end

    # prevent a service from running on boot
    # by masking in systemd & running update-rc.d
    # and whatever the equivalent is in upstart
    def mask_service(service)
      case guess_init_system
      when :systemd
        puts "Masking #{service}.service" if $VERBOSE
        FileUtils.ln_s '/dev/null', "/etc/systemd/system/#{service}.service"
        puts "Reloading systemd" if $VERBOSE
        system("systemctl daemon-reload")
      when :upstart
        puts "Doing nothing because I don't know how to mask an upstart service" if $VERBOSE
        # ???
      when :sysv
        puts "disabling #{service} on all runlevels" if $VERBOSE
        system("update-rc.d #{service} disable 2 3 4 5")
      end
    end

    # allow a service to start on boot
    # by unmasking in systemd & running update-rc.d
    # and whatever the equivalent is in upstart
    def unmask_service(service)
      case guess_init_system
      when :systemd
        puts "Unmasking #{service}.service"
        File.delete "/etc/systemd/system/#{service}.service"
        puts "Reloading systemd" if $VERBOSE
        system("systemctl daemon-reload")
      when :upstart
        # ???
      when :sysv
        puts "enabling #{service} on runlevels 3 & 5" if $VERBOSE
        system("update-rc.d #{service} enable 3 4 5")
      end

    end

    def start_service(service)
      puts "starting #{service}..." if $VERBOSE
      success = case guess_init_system
      when :systemd
        system("systemctl start #{service}")
      when :upstart
        system("initctl start #{serice}")
      when :sysv
        system("/etc/init.d/#{service} start")
      end
      puts ( success ? "ok" : "fail" ) if $VERBOSE
    end

    def stop_service(service)
      puts "stopping #{service}..." if $VERBOSE
      success = case guess_init_system
      when :systemd
        system("systemctl stop #{service}")
      when :upstart
        system("initctl stop #{serice}")
      when :sysv
        system("/etc/init.d/#{service} stop")
      end
      puts ( success ? "ok" : "fail" ) if $VERBOSE
    end


    module_function :mkdir_p, :set_param, :get_param, :random_string, :safe_open, :parse_quota, :lock, :unlock, :show_help, :show_usage, :show_manual, :show_help_or_manual

  end

end

