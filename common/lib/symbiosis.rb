#
# This module contains all the classes that are needed for Bytemark Symbiosis.
#
module Symbiosis
  def root
    @@root || '/'
  end

  def root=(new_root)
    @@root = new_root
  end

  def prefix
    @@prefix || '/srv'
  end

  def prefix=(new_prefix)
    @@prefix = new_prefix
  end

  def path_to(path)
    File.join(root, path)
  end

  def path_in_prefix_to(path)
    File.join(root, prefix, path)
  end
end
