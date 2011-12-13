
require 'symbiosis/domain'

#
# This extends the Symbiois domain class with some FTP methods.
#
module Symbiosis
  class Domain

    def ftp_username
      self.name
    end

    def ftp_chroot_dir
      File.join(self.directory, "public", ".", "")
    end

    def ftp_password_file
      File.join(self.config_dir,"ftp-password")
    end

    def ftp_enabled?
      File.readable?(self.ftp_password_file)
    end

    def ftp_password
      @ftp_password ||= nil

      if @ftp_password.nil?
        if self.ftp_enabled?
          #
          # Read the password
          #
          param = get_param("ftp-password",self.config_dir)

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
        set_param("ftp-password", @ftp_password, self.config_dir)
      else
        set_param("ftp-password", crypt_password(@ftp_password), self.config_dir)
      end

      return @ftp_password
    end
    
    #
    # Handle the quota, in bytes.
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
              quota = param.split.first.strip
              @ftp_quota = parse_quota(quota)
            rescue ArgumentError => err
              @ftp_quota = nil
            end
          end
        end
      end

      @ftp_quota
    end

    def ftp_quota=(q)
      @ftp_quota = parse_quota(q)

      set_param("ftp-quota", @ftp_quota, self.config_dir)

      return @ftp_quota
    end
    
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
