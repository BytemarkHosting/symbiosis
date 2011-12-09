require 'symbiosis/utils'
require 'etc'
#
#  Ruby class to model a domain.
#

module Symbiosis

  class Domain

    #
    # This has handy mkdir/get_param/set_param methods.
    #
    include Utils

    attr_reader :uid, :gid, :user, :group, :name, :prefix, :directory

    #
    # Constructor.
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
    # Global config directory
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
    #
    # Encrypt a password
    #
    def crypt_password(password)
      raise ArgumentError, "password must be a string" unless password.is_a?(String)
      salt = "$1$"+random_string(4)+"$"
      return "{CRYPT}"+password.crypt(salt)
    end

    #
    # Password check
    #
    def check_password(password, real_password)
      # 
      # Make sure we have a real_password set, and chop whitespace of either end.
      #
      real_password = real_password.to_s.chomp.strip
      password      = password.to_s

      #
      # Check to make sure the password isn't empty.
      #
      raise ArgumentError, "Empty password set" if real_password.empty?

      #
      # Make sure we have a password set
      #
      raise ArgumentError, "No password given" if password.empty?

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
        result = ( password.crypt( crypted_password ) == crypted_password )

        #
        # If the result was successful, or we know that we have to use crypt,
        # return the result.
        #
        return result if result or force_crypt
      end

      #
      # Fall back to a plain text comparison
      #
      return password == real_password
    end
  end
end

