
require "fileutils"

module Bytemark
  module Vhost
    module Test

      # This function uses the FileUtils mkdir_p command to make a directory.
      # It adds the extra options of :user and :group to allow these to be set
      # in one fell swoop.
      def mkdir(dir, options = {})
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
        FileUtils::chown_R options[:user], options[:group], File.join(parent,child), fu_opts
      end



      # This function generates a string of random numbers and letters from the
      # sequence A-Z, a-z, 0-9 minus 0, 1, i, l.
      def random_string( len = 10 )

        randchars = "23456789abcdefghjkmnpqrstuvwxyz"

        name=""

        len.times { name << randchars[rand(randchars.length)] }
        name
      end


      #
      # Allow arbitrary settings in /config to be retrieved
      #
      def get_param(setting, config_dir)
        fn = File.join(config_dir, setting)

        return false unless File.exists?(fn)

        #
        # Return true if the file is present and empty
        #
        return true if File.zero?(fn)

        #
        # Otherwise return the contents
        #
        return File.open(fn, "r"){|fh| fh.read}
      end

      #
      # allow setting to be set..
      #
      def set_param(setting, value, config_dir)
        fn = File.join(config_dir, setting)

        #
        # Make sure the directory exists first
        #
        raise "Config directory does not exist." unless File.exists?(config_dir)

        if value.nil?
          FileUtils.touch(fn)
        else
          File.open(fn,"w+"){|fh| fh.puts(value.to_s)}
        end

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

        #
        # Return the value we were originally given
        #
        value
      end

      module_function :mkdir, :set_param, :get_param, :random_string

    end
  end
end

