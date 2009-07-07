#!/usr/bin/ruby
#

# Add the local lib directory
$: << "../lib" if File.exists?("../lib")


require 'test/unit'

require 'tc_dovecot'
require 'tc_ftp'
require 'tc_http'
require 'tc_smtp'

