#!/usr/bin/ruby
# encoding: UTF-8

require 'iconv' unless String.instance_methods.include?(:encode)
require 'uri'
require 'symbiosis/utils'
require 'test/unit'

begin
  require 'mysql2'
rescue LoadError
  # Do nothing.
end

class TcBackupsMysql < Test::Unit::TestCase

  def setup
    #
    # These are MySQL charsets, not ruby charsets.
    #
    @charsets = %w(UTF8 LATIN1)
    @default_charset = "UTF8"
    @backup_dir = "/var/backups/mysql"
    @backup_script = File.expand_path(File.dirname(__FILE__) + "/../backup.d/pre-backup.d/10-dump-mysql")

    @database = "symbiosis test "+Symbiosis::Utils.random_string(10)+" \303\242"
    @table    = "t\303\241ble"
    @column   = "c\303\266lumn"
    @value    = "v\303\245lue"

    @defaults_file = "/etc/mysql/debian.cnf"

    @username = @password = nil
    
    @charset_map = {"UTF8" => "UTF-8", "LATIN1" => "ISO-8859-1"}

    parse_defaults_file(@defaults_file)

  end

  def teardown
    @charsets.each do |charset|
      database = @database + " #{charset}"
      drop_db(database) if has_mysql?
      dump_name = calculate_dump_name(database)
      File.unlink(dump_name) if File.exist?(dump_name)
    end
  end

  def has_mysql?
    defined? Mysql2 and Process.uid == 0
  end

  def do_conv(to, from, str)
    assert(str.is_a?(String), "#{str.inspect} is not a string")

    if str.respond_to?(:encode)
      return str.encode(@charset_map[to], @charset_map[from])
    else
      return Iconv.conv(@charset_map[to], @charset_map[from], str)
    end
  end

  def parse_defaults_file(fn)
    File.open(fn,"r") do |fh|
      found_client = false

      until fh.eof?
        line = fh.gets
        case line.chomp
          when /^\s*\[client\]/
            found_client = true
          when /^\s*\[/
            break if found_client
          when /\s*user\s*=\s*(\S+)/
            @username = $1 if found_client
          when /\s*password\s*=\s*(\S+)/
            @password = $1 if found_client
        end
      end
    end
  rescue StandardError
    @username = @password = nil
  end

  def calculate_dump_name(database, charset=@default_charset)
    File.join(@backup_dir, URI.escape(do_conv(@default_charset,charset,database),/[^a-zA-Z0-9._-]/)) + ".sql.gz"
  end

  def create_db(database, charset=@default_charset)
    dbh = Mysql2::Client.new(username: @username, password: @password, encoding: charset.downcase)
    dbh.query("CREATE DATABASE `#{database}` CHARACTER SET #{charset};")
  end

  def drop_db(database, charset=@default_charset)
    dbh = Mysql2::Client.new(username: @username, password: @password, encoding: charset.downcase)
    dbh.query("DROP DATABASE IF EXISTS `#{database}`")
  rescue Mysql2::Error => err
    warn err.to_s
  ensure
    dbh.close if dbh
  end

  def do_test_db(charset, database, table, column, value, insert_data = false)
    res = nil

    dbh = Mysql2::Client.new(username: @username, password: @password, encoding: charset.downcase)
    dbh.query "USE `#{database}`;"
    if insert_data
      dbh.query "CREATE TABLE `#{table}` (`#{column}` CHAR(20) CHARACTER SET #{charset});"
      dbh.query "INSERT INTO `#{table}` (`#{column}`) VALUES (\"#{value}\");"
    end
    res = dbh.query "SELECT * FROM `#{table}`;"
    dbh.close

    #
    # Make sure we've inserted the things properly
    #
    assert_equal(1, res.fields.count, "Mysql returned the wrong number of fields")
    assert_equal(1, res.count, "Mysql returned the wrong number of rows")

    returned_col = res.fields.first.dup
    assert_equal(column, returned_col.encode(@charset_map[charset]), "Mysql returned the wrong field name")

    returned_val = res.first[returned_col]
    assert_equal(value,  returned_val, "Mysql returned the wrong value")
  end

  #
  # This test does the following:
  #   * creates a DB
  #   * populates it
  #   * checks it was populated as expected
  #   * takes a backup (using the script)
  #   * drops the DB
  #   * restores the DB
  #   * checks it was re-populated as expected
  #
  # It checks it for databases with funny charsets used in the DB name
  #
  def test_mysql_dump
    unless has_mysql?
      puts "Not running MySQL backup tests, since not all the requirements are in place."
      return
    end

    @charsets.each do |charset|
      database = do_conv(charset, @default_charset, @database +" #{charset}")
      table = do_conv(charset, @default_charset, @table)
      column = do_conv(charset, @default_charset, @column)
      value = do_conv(charset, @default_charset, @value)

      res = nil
    
      create_db(database, charset)
      do_test_db(charset, database, table, column, value, true)

      system(@backup_script, do_conv(@default_charset,charset,database))
      assert_equal(0, $?.exitstatus, "#{@backup_script} returned non-zero.")

      drop_db(database, charset)

      dump_name = calculate_dump_name(database, charset)
      assert(File.exist?(dump_name),"Mysql dump file '#{dump_name}' does not exist.")

      create_db(database, charset)
      system("zcat #{dump_name} | /usr/bin/mysql --defaults-file=#{@defaults_file} --default-character-set=#{charset} '#{database}'")
      assert_equal(0, $?.exitstatus, "Failed to restore MySQL database from dump.")

      do_test_db(charset, database, table, column, value)

      drop_db(database, charset)
    end

  end

end
