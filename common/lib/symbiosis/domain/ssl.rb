require 'symbiosis/domain'
require 'symbiosis/ssl'
require 'symbiosis/ssl/set'
require 'openssl'
require 'tmpdir'
require 'erb'

module Symbiosis

  class Domain

    #
    # Returns true if SSL has been enabled.  SSL is enabled if there is a
    # matching key and certificate found using ssl_find_matching_certificate_and_key.
    #
    def ssl_enabled?
      return false if self.ssl_current_set.nil?

      self.ssl_current_set.certificate and self.ssl_current_set.key
    end

    #
    # Do we redirect to the SSL only version of this site?
    #
    def ssl_mandatory?
      get_param("ssl-only", self.config_dir)
    end

    def ssl_x509_certificate_file
      return nil unless self.ssl_current_set.is_a?(Symbiosis::SSL::Set)
      self.ssl_current_set.certificate_file
    end
    
    alias :ssl_certificate_file :ssl_x509_certificate_file
    
    def ssl_x509_certificate_file=(f)
      @ssl_current_set ||= Symbiosis::SSL::Set.new(self, self.config_dir)
      self.ssl_current_set.certificate_file=f
    end
    
    alias :ssl_certificate_file= :ssl_x509_certificate_file=

    def ssl_x509_certificate
      return nil unless self.ssl_current_set.is_a?(Symbiosis::SSL::Set)
      self.ssl_current_set.certificate
    end

    alias :ssl_certificate :ssl_x509_certificate

    def ssl_key_file
      return nil unless self.ssl_current_set.is_a?(Symbiosis::SSL::Set)
      self.ssl_current_set.key_file
    end
    
    def ssl_key_file=(f)
      @ssl_current_set ||= Symbiosis::SSL::Set.new(self, self.config_dir)
      self.ssl_current_set.key_file=f
    end

    def ssl_key
      return nil unless self.ssl_current_set.is_a?(Symbiosis::SSL::Set)
      self.ssl_current_set.key
    end

    def ssl_certificate_chain_file
      return nil unless self.ssl_current_set.is_a?(Symbiosis::SSL::Set)
      self.ssl_current_set.certificate_chain_file
    end

    def ssl_add_ca_path(p)
      @ssl_current_set ||= Symbiosis::SSL::Set.new(self, self.config_dir)
      self.ssl_current_set.add_ca_path(p)
    end

    def ssl_certificate_store
      return nil unless self.ssl_current_set.is_a?(Symbiosis::SSL::Set)
      self.ssl_current_set.certificate_store
    end

    def ssl_available_files
      return [] unless self.ssl_current_set.is_a?(Symbiosis::SSL::Set)
      self.ssl_current_set.available_files
    end

    def ssl_available_certificate_files
      return [] unless self.ssl_current_set.is_a?(Symbiosis::SSL::Set)
      self.ssl_current_set.available_certificate_files
    end

    def ssl_available_key_files
      return [] unless self.ssl_current_set.is_a?(Symbiosis::SSL::Set)
      self.ssl_current_set.available_key_files
    end

    def ssl_find_matching_certificate_and_key
      return [] unless self.ssl_current_set.is_a?(Symbiosis::SSL::Set)
      self.ssl_current_set.find_matching_certificate_and_key
    end

    def ssl_verify(*args)
      self.ssl_current_set.verify(*args)
    end

    #
    # Returns the SSL provider name.  If the `ssl-provider` is unset, the first
    # available provider is chosen.  If the name is set to `false` then false
    # is returned.  If no provider could be found, false is returned.  If the
    # provider name is "bad", false is returned.
    #
    def ssl_provider
      provider = get_param("ssl-provider", self.config_dir)

      return false if false == provider

      if provider.nil?
        if Symbiosis::SSL::PROVIDERS.first.to_s =~ /.*::([^:]+)$/
          provider = $1.downcase
        end
      end

      return false unless provider.is_a?(String)

      unless provider =~ /^[a-z0-9_]+$/
        warn "\tBad ssl-provider for #{self.name}" if $VERBOSE
        return false
      end

      provider.chomp
    end

    #
    # Returns the SSL provider class, or nil if `ssl-provider` is explicitly
    # set to "false" for this domain.  If `ssl-provider` class is unset, the
    # first available provider is used.  The `ssl-provider` doesn't map to a
    # class name, then nil is returned.
    #
    def ssl_provider_class
      provider_name = self.ssl_provider

      return nil if false == provider_name

      if provider_name.is_a?(String)
        provider = Symbiosis::SSL::PROVIDERS.find{|k| k.to_s =~ /::#{provider_name}$/i}
      else
        provider = Symbiosis::SSL::PROVIDERS.first
      end

      provider
    end

    #
    # This fetches the certificate from using ssl_provider_class.  If
    # ssl_provider_class does not return a suitable Class, nil is returned.
    #
    # Returns an hash of
    #
    #  { :key, :certificate, :request, :bundle}
    #
    def ssl_fetch_new_certificate(write = true)
      ssl_provider_class = self.ssl_provider_class

      unless ssl_provider_class.is_a?(Class) and
        ssl_provider_class.instance_methods.include?(:verify_and_request_certificate!)
        return nil
      end

      ssl_provider = ssl_provider_class.new(self)
      ssl_provider.register unless ssl_provider.registered?
      ssl_provider.verify_and_request_certificate!

      return { :key         => ssl_provider.key,
               :request     => ssl_provider.request,
               :bundle      => ssl_provider.bundle,
               :certificate => ssl_provider.certificate }
    end

    def ssl_write_set(set)
      #
      # Drop effective privs if needed.
      #
      Process.egid = self.gid if Process.gid == 0
      Process.euid = self.uid if Process.uid == 0

      tmpdir = Dir.mktmpdir(self.name+"-ssl-")

      raise ArgumentError, "The SSL set must contain a certificate and key as a minimum" unless set[:key] and set[:certificate]

      combined = [:certificate, :bundle, :key].map{|k| set[k]}.flatten.compact

      set_param("ssl.key",set[:key].to_pem, tmpdir) 
      set_param("ssl.crt",set[:certificate].to_pem, tmpdir)
      set_param("ssl.csr",set[:request].to_pem, tmpdir) if set[:request]
      set_param("ssl.bundle",set[:bundle].map(&:to_pem).join("\n"), tmpdir) if set[:bundle] and !set[:bundle].empty?
      set_param("ssl.combined", combined.map(&:to_pem).join("\n"), tmpdir)

      last_set = self.ssl_available_sets.last
      if last_set.nil?
        last_set = "0" 
      else
        last_set.succ!
      end

      next_set_dir = File.join(self.config_dir, "ssl", last_set)

      while File.exist?(next_set_dir)
        next_set_dir.succ!
      end

      mkdir_p(File.dirname(next_set_dir))
      FileUtils.mv(tmpdir, next_set_dir)

      Process.euid = 0 if Process.uid == 0
      Process.egid = 0 if Process.gid == 0

      return next_set_dir
    end

    #
    # We expect the certificate, key, and bundle in a pattern like
    # /srv/example.com/config/ssl/set/.
    #
    def ssl_current_set
      return @ssl_current_set if defined? @ssl_current_set and @ssl_current_set.is_a?(Symbiosis::SSL::Set)

      current_dir = File.join(self.config_dir, "ssl", "current")
      stat = nil

      begin
        stat = File.lstat(current_dir)
      rescue Errno::ENOENT
        return self.ssl_legacy_set
      end

      while stat.symlink? do
        parent_dir  = File.dirname(current_dir)
        current_dir = File.expand_path(File.readlink(current_dir), parent_dir)
        begin
          stat = File.lstat(current_dir)
        rescue Errno::ENOENT
          break
        end
      end

      this_set = nil
      begin
        this_set = Symbiosis::SSL::Set.new(self, current_dir)
      rescue StandardError => err
        warn "\t#{err.to_s} -- ignoring SSL set in #{current_dir} for #{self.name}" if $VERBOSE
        return self.ssl_legacy_set
      end
      
      begin
        this_set.verify(this_set.certificate, this_set.key, this_set.certificate_store, true)
      rescue OpenSSL::OpenSSLError => err
        warn "\tUnable to verfity set in #{current_dir} for #{self.name}" if $VERBOSE
        return self.ssl_legacy_set
      end

      return self.ssl_legacy_set if this_set.nil?

      this_set
    end

    def ssl_legacy_set
      this_set = Symbiosis::SSL::Set.new(self, self.config_dir)

      this_set.verify(this_set.certificate, this_set.key, this_set.certificate_store, true)

      this_set
    rescue OpenSSL::OpenSSLError => err
      warn "\t#{err.to_s}" if $VERBOSE
      nil
    end

    #
    # Returns the directory
    #
    def ssl_available_sets
      sets = []

      Dir.glob(File.join(self.config_dir, 'ssl' ,'*')).each do |cert_dir|

        this_set = Symbiosis::SSL::Set.new(self, cert_dir)

        #
        # Always miss out the "current" set
        #
        next if this_set.name == "current"

        #
        # If this certificate verifies, add it to our list
        #
        begin
          this_set.verify(this_set.certificate, this_set.key, this_set.certificate_store, true)
        rescue OpenSSL::OpenSSLError => err
          warn "\t#{err.to_s}" if $VERBOSE
          next
        end

        sets << this_set
      end

      return sets.sort
    end

    #
    # This method symlinks /srv/example.com/config/ssl/current to the latest
    # set of certificates discovered by #ssl_available_sets. This returns true
    # if a rollover was performed, or false otherwise.
    #
    def ssl_rollover
      current = self.ssl_current_set
      latest  = self.ssl_available_sets.last

      if latest.nil?
        warn "\tNo valid sets of certificates found." if $VERBOSE
        return false
      end

      #
      # If the current certificate is current, do nothing.
      #
      return false if current.name == latest.name

      current_dir = File.join(self.config_dir, "ssl", "current")

      begin
        stat = File.lstat(current_dir)
      rescue Errno::ENOENT
        stat = nil
      end

      unless stat.nil? or stat.symlink?
        warn "\t#{current_dir} is not a symlink.  Unwilling to roll over." if $VERBOSE
        return false
      end

      #
      # To create a symlink with the correct uid/gid when running as root, we
      # need to set our effective UID/GID.
      #
      Process.egid = self.gid if Process.gid == 0
      Process.euid = self.uid if Process.uid == 0

      File.unlink(current_dir) unless stat.nil?
      File.symlink(latest.name, current_dir)

      Process.euid = 0 if Process.uid == 0
      Process.egid = 0 if Process.gid == 0

      return true
    end

  end

end
