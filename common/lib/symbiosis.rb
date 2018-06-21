#
# This module contains all the classes that are needed for Bytemark Symbiosis.
#
module Symbiosis
  @@etc = '/etc'
  @@prefix='/srv' 

  def self.etc
    @@etc
  end

  def self.etc=(new_etc)
    @@etc = new_etc
  end

  def self.prefix
    @@prefix
  end

  def self.prefix=(new_prefix)
    @@prefix = new_prefix
  end

  def self.path_in_etc(*path)
    File.join(etc, path)
  end

  def self.path_in_prefix(*path)
    File.join(prefix, path)
  end
end
