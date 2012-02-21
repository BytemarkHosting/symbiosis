
require 'symbiosis/domain'

module Symbiosis

  class Domain

    #
    # Returns the FTP username, i.e. the domain name.
    #
    def ftp_username
      self.name
    end

    #
    # Returns the FTP chroot directory.  Currently defaults to
    # self.directory/public/./
    #
    def ftp_chroot_dir
      File.join(self.directory, "public", ".", "")
    end

    #
    # Returns the name of the FTP password file.
    #
    def ftp_password_file
      File.join(self.config_dir,"ftp-password")
    end

    #
    # Checks to see if FTP has been enabled for this domain.
    #
    def ftp_enabled?
      File.readable?(self.ftp_password_file)
    end

    #
    # Returns the FTP password as a string, or nil if no password could be
    # found.
    #
    def ftp_password
      @ftp_password ||= nil

      if @ftp_password.nil?
        if self.ftp_enabled?
          #
          # Read the password
          #
          param = get_param("ftp-password", self.config_dir, {:mode => 0600})

          unless param.is_a?(String)
            @ftp_password = nil
          else
            @ftp_password = param.split($/).first.strip
          end
        end
      end

      @ftp_password
    end

    #
    # Set the FTP password.  Plaintext is for testing only, really.
    #
    def ftp_password=(f, plaintext = false)
      @ftp_password = f

      if plaintext
        set_param("ftp-password", @ftp_password, self.config_dir, {:mode => 0600})
      else
        set_param("ftp-password", crypt_password(@ftp_password), self.config_dir, {:mode => 0600})
      end

      return @ftp_password
    end
    
    #
    # Return the FTP quota.  Uses Symbiois::Utils#parse_quota to do the
    # parsing.  Returns an Integer, or nil if no quota was set.
    #
    def ftp_quota
      if ! defined? @ftp_quota or @ftp_quota.nil?
        if self.ftp_enabled?
          #
          # Read the quota
          #
          param = get_param("ftp-quota",self.config_dir)

          unless param.is_a?(String)
            @ftp_quota = nil
          else
            begin
              @ftp_quota = parse_quota(param)
            rescue ArgumentError => err
              @ftp_quota = nil
            end
          end
        end
      end

      @ftp_quota
    end

    #
    # Sets the quota.  Uses Symbiois::Utils#parse_quota to check it can be
    # parsed.  Returns the parsed Integer, or nil if no quota was set.
    #     
    #
    def ftp_quota=(q)
      if q.nil?
        @ftp_quota = nil
      else
        @ftp_quota = parse_quota(q)
      end

      set_param("ftp-quota", q, self.config_dir)

      return @ftp_quota
    end
   
    #
    # Check the password, and create the chroot'd directory if the password
    # check succeeds.
    #
    # Raises an ArgumentError if the password is wrong.
    #
    # Returns true on success.
    #
    def ftp_login(password)
      #
      # Do the password check.
      #
      raise ArgumentError, "Bad password" unless check_password(password, self.ftp_password)

      #
      # OK, we've successfully logged in.  Create the directory
      #
      create_dir(File.expand_path(ftp_chroot_dir)) unless File.directory?(ftp_chroot_dir)

      return true
    end

  end

end
