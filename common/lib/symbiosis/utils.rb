
require "fileutils"

module Symbiosis

  #
  # This module has a number of useful methods that are used everywhere.
  #
  module Utils

    # 
    # This function uses the FileUtils mkdir_p command to make a directory.
    # It adds the extra options of :user and :group to allow these to be set
    # in one fell swoop.
    #
    def mkdir_p(dir, options = {})
      # Switch on verbosity..
      options[:verbose] = true if $DEBUG

      
      # Find the first directory that exists, and the first non-existent one.
      parent = File.expand_path(dir)
      parent, child = File.split(parent) while !File.exists?(parent) 
      # Then set the options such that the uid/gid of the parent dir can be propagated.
      parent_s = File.stat(parent)
      options[:user]  = parent_s.uid.to_s if options[:user].nil?
      options[:group] = parent_s.gid.to_s if options[:group].nil?

      # Make the directory
      fu_mkdir_opts = [:noop, :verbose, :mode]
      fu_opts = {}
      options.find_all{|k,v| fu_mkdir_opts.include?(k)}.each{|k,v| fu_opts[k] = v}
      FileUtils::mkdir_p dir, fu_opts

      # Set the permissions
      fu_chown_opts = [:noop, :verbose]
      fu_opts = {}
      options.find_all{|k,v| fu_chown_opts.include?(k)}.each{|k,v| fu_opts[k] = v}
      FileUtils::chown_R options[:user], options[:group], File.join(parent.to_s,child.to_s), fu_opts
    end

    # 
    # This function generates a string of random numbers and letters from the
    # sequence A-Z, a-z, 0-9 minus 0, O, o, 1, I, l.
    #
    def random_string( len = 10 )
      raise ArgumentError, "length must be an integer" unless len.is_a?(Integer)

      randchars = "23456789abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"

      name=""

      len.times { name << randchars[rand(randchars.length)] }

      name
    end

    #
    # Allow arbitrary parameters in config_dir to be retrieved.
    #
    # * false is returned if the file does not exist, or is not readable
    # * true is returned if the file exists, but is of zero length
    # * otherwise the files contents are returned as a string.
    #
    #
    def get_param(setting, config_dir)
      fn = File.join(config_dir, setting)

      #
      # Return false unless we can read the file
      #
      return false unless File.exists?(fn) and File.readable?(fn)

      #
      # Return true if the file is present and empty
      #
      return true if File.zero?(fn)

      #
      # Otherwise return the contents
      #
      return File.open(fn, "r"){|fh| fh.read}.to_s
    end

    #
    # Records a parameter.
    #
    #  * true is stored as an empty file
    #  * false or nil causes the file to be removed, if it exists.
    #  * Anything else is converted to a string and stored.
    #
    # If a file is created, or written to, then the permissions are set such
    # that the file is owned by the same owner/group as the config_dir, and
    # readable by everyone, but writable only by the owner (0644).
    #
    def set_param(setting, value, config_dir)
      fn = File.join(config_dir, setting)

      #
      # Make sure the directory exists first
      #
      raise "Config directory does not exist." unless File.exists?(config_dir)

      if true == value
        FileUtils.touch(fn)
      elsif false == value or value.nil?
        File.unlink(fn) if File.exists?(fn)
      else
        File.open(fn,"w+"){|fh| fh.puts(value.to_s)}
      end

      if File.exists?(fn)
        #
        # Make sure permissions are OK
        #
        fs = File.stat(config_dir)

        #
        # Set up some verbose output if we're debugging
        #
        options = {}
        options[:verbose] = true if $DEBUG
        FileUtils::chown  fs.uid.to_s, fs.gid.to_s,  fn, options
        FileUtils::chmod  0644, fn, options
      end

      #
      # Return the value we were originally given
      #
      value
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
          when "k": 1e3
          when "M": 1e6
          when "G": 1e9
          when "T": 1e12
          when "P": 1e15
          when "ki": 2**10
          when "Mi": 2**20
          when "Gi": 2**30
          when "Ti": 2**40
          when "Pi": 2**50
          else 1
        end

        return (n*m).round.to_i
      elsif quota.is_a?(String)
        raise ArgumentError, "Cannot parse quota #{quota.inspect}"
      else
        raise ArgumentError, "parse_quota requires either a String or Numeric argument"
      end
    end

    module_function :mkdir_p, :set_param, :get_param, :random_string, :parse_quota

  end

end

