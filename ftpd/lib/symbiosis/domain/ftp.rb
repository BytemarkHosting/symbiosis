
require 'symbiosis/domain'
require 'symbiosis/utils'

module Symbiosis

  class Domain

    class FTPUser

      #
      # This has handy mkdir/get_param/set_param methods.
      #
      include Symbiosis::Utils


      attr_reader :username, :domain, :password, :chroot_dir, :quota

      def initialize(username, domain, password, chroot_dir=nil, quota=nil)
        self.domain = domain
        self.username = username
        self.password = password

        # Set the default directory to a chrooted public dir.
        self.chroot_dir = chroot_dir

        # And there is no default quota.
        self.quota = quota
      end

      def domain=(d)
        raise ArgumentError, "Not a Symbiosis Domain" unless d.is_a?(Symbiosis::Domain)
        @domain = d
      end

      def password=(pw)
        pw = pw.to_s

        if pw.empty?
          @password = nil;
        else 
          @password = pw
        end
      end

      def username=(u)
        u = u.to_s
        raise ArgumentError, "Empty FTP username" if u.empty?
        @username = u
      end

      def chroot_dir
        @chroot_dir ||= nil

        self.chroot_dir = domain.ftp_chroot_dir if @chroot_dir.nil?

        @chroot_dir
      end

      def chroot_dir=(d)
        d = d.to_s

        if d.empty?
          @chroot_dir = nil
          return @chroot_dir
        end

        #
        # If the directory is relative, prefix it with the domain's directory.
        # 
        unless d.start_with? "/"
          d = File.join(self.domain.public_dir,d,"./")
        end

        @chroot_dir = d
      end

      def quota
        if @quota.nil?
          #
          # Read the domain's default quota
          #
          param = get_param("ftp-quota",domain.config_dir)

          if param.is_a?(String)
            self.quota = param
          end
        end
      
        @quota
      end

      def quota=(q)
        @quota ||= nil

        if q.is_a?(Integer)
          @quota = q
        elsif q.is_a?(String)
          begin
            @quota =  Symbiosis::Utils.parse_quota(q)
          rescue ArgumentError => err
            @quota = nil
          end
        end

        @quota
      end

      def uid
        @domain.uid
      end

      def gid
        @domain.gid
      end

      def is_single_user?
        self.domain.name == self.username
      end

      def to_s
        [self.username, self.password, self.chroot_dir, self.quota].join(":")
      end

      #
      # Check the password, and create the chroot'd directory if the password
      # check succeeds.
      #
      # Raises an ArgumentError if the password is wrong.
      #
      # Returns true on success.
      #
      def login(password)
        #
        # Do the password check.
        #
        if true === domain.check_password(password, self.password)
  
          #
          # OK, we've successfully logged in.  Create the directory
          #
          domain.create_dir(File.expand_path(self.chroot_dir)) unless File.directory?(self.chroot_dir)
  
          return true
        else
          return false
        end
      end

    end


    #
    # Return the default FTP quota for the domain.
    #
    def ftp_quota
      if ftp_single_user?
        ftp_single_user.quota
      else
        nil
      end
    end

    #
    # Returns the FTP chroot directory.  Currently defaults to
    # the domain's public directory.
    #
    def ftp_chroot_dir
      File.join(self.public_dir, "./")
    end

    #
    # Returns the name of the FTP password file.
    #
    def ftp_password_file
      File.join(self.config_dir,"ftp-password")
    end
    
    #
    # Returns true if the domain is enabled for single or multi user Ftp
    #
    def ftp_enabled?
      ftp_single_user? or ftp_multi_user?
    end
    
    #
    # Returns the name of the FTP password file.
    #
    def ftp_users_file
      File.join(self.config_dir,"ftp-users")
    end

    #
    # Checks to see if single-user FTP has been enabled for this domain.
    #
    def ftp_single_user?
      File.readable?(self.ftp_password_file) 
    end
    
    #
    # Checks to see if multi-user FTP has been enabled for this domain.
    #
    def ftp_multi_user?
      File.readable?(self.ftp_users_file) 
    end

    #
    # Returns an array of FTP multi users for this domain
    #
    def ftp_multi_users
      return [] unless ftp_multi_user?

      param = get_param("ftp-users", self.config_dir, {:mode => 0600})

      return [] unless param.is_a?(String)

      lines = param.split($/)

      fusers = []

      lines.each do |l|
        (fuser, fpasswd, fdir, fquota) = l.strip.split(":",5)
        fusers << FTPUser.new(fuser+"@"+self.name, self, fpasswd, fdir, fquota)
      end

      fusers
    end

    #
    # Returns the old-style single FTP user for this domain.
    #
    def ftp_single_user
      return nil unless ftp_single_user?

      param = get_param("ftp-password", self.config_dir, {:mode => 0600})

      unless param.is_a?(String)
        passwd = nil
      else
        passwd = param.split($/).first.strip
      end

      return FTPUser.new(self.name, self, passwd, self.public_dir, nil)
    end

  end

end
