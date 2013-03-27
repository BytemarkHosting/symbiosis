require 'symbiosis/utils'
require 'symbiosis/host'
require 'etc'

module Symbiosis

  #
  #  Ruby class to model a Symbiosis domain.
  #
  class Domain

    #
    # This has handy mkdir/get_param/set_param methods.
    #
    include Utils

    attr_reader :uid, :gid, :user, :group, :name, :prefix, :directory, :symlink

    #
    # This is a regular expression that matches valid domain names.
    #
    NAME_REGEXP = /^[a-z0-9-]+\.([a-z0-9-]+\.?)+$/i

    #
    # Creates a new domain object.  If no name is set a random domain name is
    # generated, based on 10 characters in the imaginary <code>.test</code> TLD.
    #
    def initialize( name = nil, prefix = "/srv" )
      #
      # Make sure our prefix exists
      #
      @prefix = File.expand_path(prefix)
      raise Errno::ENOENT, @prefix unless File.directory?(@prefix)

      #
      # If no name is set, asssign a random new one.
      #
      if name.nil?
        @name = random_string(10).downcase+".test" 
      else
        @name = name
      end

      #
      # Make sure the name is a valid domain name.
      #
      unless @name =~ NAME_REGEXP
        raise ArgumentError, "Bad name '#{@name.inspect}'"
      end

      #
      # Determine where the directory is.
      #
      @directory = File.join(@prefix, @name)

      #
      # If @directory (above) is a symlink, its original location is recorded
      # in @symlink.
      #
      @symlink   = nil

      #
      # If the directory exists, then check that we're not following a symlink.
      #
      if File.directory?(@directory)
        #
        # Redirect elsewhere if we have a symlink.  Expand it up relative to
        # @prefix.
        #
        if File.lstat(@directory).ino != File.stat(@directory).ino
          #
          # Deal with multiple layers of indirection with an inode comparison
          # would work better.  This will only work within the prefix
          # directory!
          #
          #
          # Work out which inode we're pointed at.  Use stat so we follow the link.
          #
          target_inode = File.stat(@directory).ino

          #
          # Now find a matching entry inode.
          #
          new_directory = Dir.glob( File.join(@prefix,"*") ).find do |entry|
            #
            # Check the inodes -- use lstat so we stat actual links without
            # following.
            #
            File.lstat(entry).ino == target_inode
          end

          #
          # If we've found a directory, record it.
          #
          unless new_directory.nil?
            #
            # Seems OK :)  Record our results.
            #
            @symlink   = @directory
            @directory = new_directory
          end
        end

        @uid  = File.stat(@directory).uid
        @user = Etc.getpwuid(@uid).name
        raise ArgumentError, "#{@directory} owned by a system user (UID less than 1000)" if @uid < 1000

        @gid = File.stat(@directory).gid
        @group = Etc.getgrgid(@gid).name
        raise ArgumentError, "#{@directory} owned by a system group (GID less than 1000)" if @gid < 1000
      else
        #
        # Otherwise assume admin.
        #
        if Process.uid < 1000
          @user = @group = "admin"
          #
          # This will raise an argument error if "admin" user/group cannot be found
          #
          @uid = Etc.getpwnam(@user).uid
          @gid = Etc.getgrnam(@group).gid
        else
          #
          # This is good for testing.
          #
          @uid   = Process.uid
          @user  = Etc.getpwuid(@uid).name
          # User's default group.
          @gid   = Etc.getpwuid(@uid).gid
          @group = Etc.getgrgid(@gid).name
        end
      end
    end

    #
    # Global config directory.  Defaults to self.directory/config
    #
    def config_dir
      File.join(self.directory,"config")
    end

    #
    # Public directory -- this is where non-private stuff is stored, i.e. logs
    # and htdocs, mostly.
    #
    def public_dir
      File.join(self.directory, "public")
    end

    #
    # Domains logfile directory.  Defaults to self.directory/public/logs
    #
    def log_dir
      File.join(self.public_dir, "logs")
    end

    #
    # Create the /srv/ directory if we're supposed to.
    #
    def create
      create_dir(self.config_dir) unless self.exists?
    end

    #
    # Destroy if necessary
    #
    def destroy
      FileUtils.rm_rf(self.directory) if self.exists?
    end

    #
    # Does the domain name exist locally?
    #
    def exists?
      File.directory?(self.directory)
    end

    #
    # Create directories using our default uid/gid
    #
    def create_dir(d, mode = 0755)
      mkdir_p(d, {:user => @user, :group => @group, :mode => mode})
    end

    #
    # Return the filename of the IP file, or nil if none has been set.
    #
    def ip_file
      if get_param("ip",self.config_dir)
        File.join(config_dir, "ip")
      else
        nil
      end
    end


    #
    # Return all this domain's IPs (IPv4 and 6) as an array.  If none have been
    # set, then the host's primary IPv4 and IPv6 addresses are returned.
    #
    def ips
      param = get_param("ip",self.config_dir)
      @ip_addresses = []

      if param.is_a?(String)     
        param.split.each do |l|
          begin
            ip = IPAddr.new(l.strip)
            @ip_addresses << ip
          rescue ArgumentError => err
            # should probably warn at this point..
          end
        end
      end

      #
      # If no IP addresses were found, use the primary IPs.
      #
      if @ip_addresses.empty?
        @ip_addresses << Symbiosis::Host.primary_ipv4
        @ip_addresses << Symbiosis::Host.primary_ipv6
      end

      #
      # Remove nils.
      #
      @ip_addresses = @ip_addresses.compact

      @ip_addresses
    end

    #
    # Returns the first IPv4 address, or the first IPv6 address if no IPv4
    # addresses are defined, or nil.
    #
    def ip
      self.ipv4.first || self.ipv6.first
    end

    #
    # Return this domain's IPv4 addresses as an array
    #
    def ipv4
      self.ips.select{|ip| ip.ipv4?}
    end

    #
    # Return this domains IPv6 addresses as an array.
    #
    def ipv6
      self.ips.select{|ip| ip.ipv6?}
    end

    #
    # Encrypt a password, using the cyrpt() function, with MD5 hashing and an 8
    # character salt.  The function returns the crypt() output, prepended with
    # <code>{CRYPT}</code>.
    #
    def crypt_password(password)
      raise ArgumentError, "password must be a string" unless password.is_a?(String)
      salt = "$1$"+random_string(8)+"$"
      return "{CRYPT}"+password.crypt(salt)
    end

    #
    # Checks a given password against the real one, which may be hashed using
    # crypt_password.  An argument error is raised if either password is empty.
    #
    # First the two passwords are compared using crypt(), and if that fails,
    # then a plain text comparison is made.
    #
    # If the real password starts with <code>{CRYPT}</code> or a recognisable
    # salt, i.e.  something like <code>$1$salt$</code> then only the crypted
    # comparison is done.
    #
    # If the real password contains characters other than those allowed in
    # crypt()'d hashes, just the plain text comparison is made.
    #
    # Returns true or false.
    #
    def check_password(given_password, real_password)
      # 
      # Make sure we have a real_password set, and chop whitespace of either end.
      #
      real_password = real_password.to_s.chomp.strip
      given_password      = given_password.to_s

      #
      # Check to make sure the password isn't empty.
      #
      raise ArgumentError, "Empty password set" if real_password.empty?

      #
      # Make sure we have a password set
      #
      raise ArgumentError, "No password given" if given_password.empty?

      # 
      # Check the password, crypt first, plaintext second.
      #
      if real_password =~ /^(\{(?:crypt|CRYPT)\})?((\$(?:1|2a|5|6)\$[a-zA-Z0-9.\/]{1,16}\$)?[a-zA-Z0-9\.\/]+)$/
        crypt = $1.to_s
        crypted_password = $2
        salt =  $3.to_s

        #
        # Force crypt if then string starts with {CRYPT} or $1$salt$
        #
        force_crypt   = (!crypt.empty? or !salt.empty?)

        #
        # Do the comparison
        #
        result = ( given_password.crypt( crypted_password ) == crypted_password )

        #
        # If the result was successful, or we know that we have to use crypt,
        # return the result.
        #
        return result if result or force_crypt
      end

      #
      # Fall back to a plain text comparison
      #
      return (given_password == real_password)
    end

    def aliases
      results = []

      #
      # If our domain is real, see what symlinks are pointing at it.
      #
      if File.directory?(self.directory)  

        self_stat = File.stat(self.directory)

        #
        #  For each domain.
        #
        Dir.glob( File.join(self.prefix,"*") ) do |entry|
          #
          # Skip entry if it isn't a directory
          #
          next unless File.directory?(entry)

          #
          # Check the inodes.
          #
          target_stat = File.stat(entry)
          target_lstat = File.lstat(entry)

          #
          # Skip unless the target is a link (i.e. stat and lstat inodes differ)
          # and the stat inode matches our own stat inode.
          #
          next unless target_lstat.ino != target_stat.ino and target_stat.ino == self_stat.ino 

          #
          # Split
          #
          this_prefix, this_domain = File.split(entry)

          #
          # Don't want dotfiles.
          #
          next if this_domain =~ /^\./ 
      
          #
          # And record.
          #
          results << this_domain
        end
      end

      #
      # Now run through the results, adding "www." to each if there is nothing el
      #
      ([self.name] + results).each do |this_domain|
        next if this_domain =~ /^www\./

        #
        # Add on www.
        #
        this_domain = "www."+this_domain

        #
        # Skip if we've already found it.
        #
        next if results.include?(this_domain)

        #
        # Skip if we've not already found it, but it exists on the system.
        #
        next if File.exists?(File.join(self.prefix, this_domain))

        #
        # OK add it!
        #
        results << this_domain
      end

      results.sort.uniq
    end

    #
    # Returns if this domain is in fact a symlink to another.
    #
    def is_alias?
      not self.symlink.nil?
    end

    #
    # Returns the domain name as a string.
    # 
    def to_s ; self.name.to_s ; end
  end
end

