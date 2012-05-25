#!/usr/bin/ruby

require 'iconv'
require 'uri'
require 'symbiosis/utils'
require 'test/unit'

begin
  require 'mysql'
rescue LoadError
  # Do nothing.
end

class TcBackupsMysql < Test::Unit::TestCase

  def setup
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

    parse_defaults_file(@defaults_file)

  end

  def teardown
    @charsets.each do |charset|
      database = @database + " #{charset}"
      drop_db(database) if has_mysql?
      dump_name = calculate_dump_name(database)
      File.unlink(dump_name) if File.exists?(dump_name)
    end
  end

  def has_mysql?
    defined? Mysql and 
      @username and @password 
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
    File.join(@backup_dir, URI.escape(Iconv.conv(@default_charset,charset,database),/[^a-zA-Z0-9._-]/)) + ".sql.gz"
  end

  def drop_db(database, charset=@default_charset)
    dbh = Mysql.new(nil, @username, @password)
    dbh.query("SET NAMES #{charset}")
    dbh.query("SET CHARSET #{charset}")
    dbh.query("DROP DATABASE IF EXISTS `#{database}`")
  rescue Mysql::Error => err
    warn err.to_s
  ensure
    dbh.close if dbh
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
      database = Iconv.conv(charset, @default_charset, @database) + " #{charset}"
      table = Iconv.conv(charset, @default_charset, @table)
      column = Iconv.conv(charset, @default_charset, @column)
      value = Iconv.conv(charset, @default_charset, @value)
      res = nil

      assert_nothing_raised("Failure when creating MySQL DB to test backups.") {
        dbh = Mysql.new(nil, @username, @password)
        dbh.query("SET CHARSET #{charset}")
        dbh.query("SET NAMES #{charset}")
        dbh.query("CREATE DATABASE `#{database}` CHARACTER SET #{charset};")
        dbh.query "USE `#{database}`;"
        dbh.query "CREATE TABLE `#{table}` (`#{column}` CHAR(20) CHARACTER SET #{charset});"
        dbh.query "INSERT INTO `#{table}` (`#{column}`) VALUES (\"#{value}\");"
        res = dbh.query "SELECT * FROM `#{table}`;"
        dbh.close
      }

      #
      # Make sure we've inserted the things properly
      #
      assert_equal(1, res.num_fields, "Mysql returned the wrong number of fields")
      assert_equal(1, res.num_rows, "Mysql returned the wrong number of rows")
      assert_equal(column, res.fetch_fields.first.name, "Mysql returned the wrong field name")
      assert_equal(value,  res.fetch_row.first, "Mysql returned the wrong value")

      system(@backup_script, Iconv.conv(@default_charset,charset,database))
      assert_equal(0, $?, "#{@backup_script} returned non-zero.")

      drop_db(database, charset)
 
      dump_name = calculate_dump_name(database, charset) 
      assert(File.exists?(dump_name),"Mysql dump file '#{dump_name}' does not exist.")    

      system("zcat #{dump_name} | /usr/bin/mysql --defaults-extra-file=/etc/mysql/debian.cnf")
      assert_equal(0, $?, "Failed to restore MySQL database from dump.")

      res = nil

      assert_nothing_raised("Failure when reconnecting to MySQL DB to test backups.") {
        dbh = Mysql.new(nil, @username, @password)
        dbh.query("SET CHARSET #{charset};")
        dbh.query("SET NAMES #{charset};")
        dbh.query "USE `#{database}`;"
        res = dbh.query "SELECT * FROM `#{table}`;"
        dbh.close
      }

      #
      # Make sure we've inserted the things properly
      #
      assert_equal(1, res.num_fields, "Mysql returned the wrong number of fields")
      assert_equal(1, res.num_rows, "Mysql returned the wrong number of rows")
      assert_equal(column, res.fetch_fields.first.name, "Mysql returned the wrong field name")
      assert_equal(value,  res.fetch_row.first, "Mysql returned the wrong value")
    
    end

  end
  
end
