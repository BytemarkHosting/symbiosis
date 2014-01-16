
require 'symbiosis/domain'

module Symbiosis

  class Domain
    class FTPUser

      attr_accessor :username,:password,:dir,:mode

      def initialize(username, domain, password, dir=domain.public_dir, mode="rw", quota=0)
        raise ArgumentError, "Not a Domain" unless domain.is_a?(Symbiosis::Domain)
        raise ArgumentError, "No Password" if password.nil? or password.length == 0
        raise ArgumentError, "No Username" if username.nil? or username.length == 0

        @domain = domain
        @username = username
        @password = password
        @dir = dir || (File.join(@domain.public_dir,"./"))
        unless @dir.start_with? "/"
          @dir = File.join(@domain.public_dir,@dir,"./")
        end
        @mode = mode || "rw"
        @quota = Symbiosis::Utils.parse_quota(quota || 0)
      end

      def uid
        @domain.uid
      end

      def quota
        @quota.to_i
      end

      def quota=(q)
        @quota = Symbiosis::Utils.parse_quota(q)
      end

      def gid
        @domain.gid
      end

      def to_s
        [@username,@password,@dir,@mode,quota].join(":")
      end

      def save!
        users_file = File.join(@domain.config_dir,Symbiosis::Domain::FTP_MULTI_USER_FILENAME)

        if @domain.ftpusers.find{|u|u.username == self.username}
          # then there's already a user which matches, update it
          Symbiosis::Utils.safe_open(users_file,"a+") do |uf|
            Symbiosis::Utils.lock(uf)
            buf = uf.readlines.map do |u|
              tst_user = FTPUser.create_from_string(@domain,u)
              if tst_user.username == self.username
                self.to_s # if same username, overwrite with self
              else
                u # otherwise just leave it untouched
              end
            end
            uf.rewind
            uf.truncate(0) # mandatory
            p buf
            buf.each do |f|
              uf.puts f
            end
          end
        else
          # then we need to add it
          Symbiosis::Utils.safe_open(users_file,"a+") do |uf|
            Symbiosis::Utils.lock(uf)
            uf.puts(self.to_s)
          end
        end
      end

      def self.create_from_string(domain, s)
        raise ArgumentError unless domain.is_a?(Symbiosis::Domain)
        (suser, spasswd, sdir, smode, squota) = s.strip.split(":",5)
        return FTPUser.new(suser, domain, spasswd, sdir, smode, squota)
      end
    end

    FTP_MULTI_USER_FILENAME = "ftp-users"
    FTP_SINGLE_USER_FILENAME = "ftp-password"
    FTP_SINGLE_USER_QUOTA_FILENAME = "ftp-quota"

    def ftp_multi_user?
      # Does this domain use the new "multi user" config file format?
      File.exists?(File.join(self.config_dir,FTP_MULTI_USER_FILENAME))
    end

    def ftp_single_user?
      # Does this domain use the old single ftp-password file?
      return false if ftp_multi_user? # old format has lower precedence
      File.exists?(File.join(self.config_dir,FTP_SINGLE_USER_FILENAME))
    end

    def ftp_mode
      if ftp_multi_user?
        :multi
      elsif ftp_single_user?
        :single
      else
        :none
      end
    end

    def ftp_quota(username=self.name)
      ftpusers.find{|u|u.username == username}.quota
    end

    def ftp_login(password,username=self.name)
      ftpusers.find do |u|
        u.username == username and check_password(password,u.password)
      end
    end

    def ftp_enabled?
      ftp_multi_user? or ftp_single_user?
    end

    def ftpusers
      users = []
      if ftp_multi_user?
        users = []
        safe_open(File.join(self.config_dir, FTP_MULTI_USER_FILENAME)) do |uf|
          uf.lines.each do |l|
            users << Domain::FTPUser.create_from_string(self, l)
          end
        end
        return users
      elsif ftp_single_user? # go with the crappy old-style way
        passwd = Utils.safe_open(File.join(self.config_dir, FTP_SINGLE_USER_FILENAME)) do |pf|
          pf.read.strip
        end
        quota_file = File.join(self.config_dir, FTP_SINGLE_USER_QUOTA_FILENAME)
        quota = nil
        if File.exists?(quota_file)
          quota = Utils.safe_open(quota_file) do |qf|
            qf.read.strip
          end
        end
        users << Domain::FTPUser.new(self.name,self, passwd,self.public_dir,"rw",quota)
        return users
      else
        return []
      end
    end
  end
end
