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

    attr_reader :uid, :gid, :user, :group, :name, :prefix, :directory

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
      # Determine where the directory is.
      #
      @directory = File.join(@prefix, @name)

      if File.directory?(@directory)
        #
        # If the directoy exists, then work out our uid/gid 
        #

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
    # set, then the host's first primary IPv4 and IPv6 addresses are returned.
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

      if @ip_addresses.empty?
        @ip_addresses << Symbiosis::Host.ipv4_addresses.first
        @ip_addresses << Symbiosis::Host.ipv6_addresses.first
      end

      #
      # Remove nils.
      #
      @ip_addresses.compact

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
      if real_password =~ /^(\{CRYPT\})?((\$(?:1|2a|5|6)\$[a-zA-Z0-9.\/]{1,16}\$)?[a-zA-Z0-9\.\/]+)$/
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
      return given_password == real_password
    end

    #
    # Returns the domain name as a string.
    # 
    def to_s ; self.name.to_s ; end
  end
end

