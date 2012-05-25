#!/usr/bin/ruby

require 'iconv'
require 'uri'
require 'etc'
begin
  require 'pg'
  HAS_POSTGRES = true
rescue LoadError
  HAS_POSTGRES = false
end

require 'symbiosis/utils'
require 'test/unit'

class MyTest < Test::Unit::TestCase

  def setup
    @charsets = %w(UTF8 LATIN1)
    @default_charset = "UTF8"
    @backup_dir = "/var/backups/postgresql"
    @backup_script = File.expand_path(File.dirname(__FILE__) + "/../backup.d/pre-backup.d/20-dump-postgres")

    @database = "symbiosis test "+Symbiosis::Utils.random_string(10)
    @table    = "t\303\241ble"
    @column   = "c\303\266lumn"
    @value    = "v\303\245lue"

    @dbs_created = false
  end

  def teardown
    @charsets.each do |charset|
      database = Iconv.conv(charset, @default_charset, @database) + " #{charset}"
      drop_db(database, charset) if @dbs_created
      dump_name = calculate_dump_name(database)
      File.unlink(dump_name) if File.exists?(dump_name)
    end
  end

  def chuid(u)
    begin 
      user = Etc.getpwnam(u)
      group = Etc.getgrnam(u)
    rescue ArgumentError => err
      #
      # We've not found the postgres user -- postgres is not installed.
      #
      flunk "user/group #{u} not found" 
    end

    #
    # Change user id to postgres
    #
    unless 0 == Process.uid
      flunk "Unable to drop privileges if not running as root." 
    end

    #
    # Try to drop privs.
    #
    begin
      Process::Sys.setegid(group.gid) 
      Process::Sys.seteuid(user.uid)
    rescue Errno::EPERM => err
      flunk "Unable to drop privileges from #{Process.uid}:#{Process.gid} to #{user.uid}:#{group.gid}" 
    end
  end

  def drop_db(database, charset=@default_charset)
    chuid("postgres")
    dbh = PGconn.new(:dbname => "postgres")
    dbh.set_client_encoding(charset)
    dbh.exec "DROP DATABASE IF EXISTS \"#{database}\""
  rescue PGError => err
    warn err.to_s
  ensure
    dbh.finish
    chuid("root")
  end

  def calculate_dump_name(database)
    File.join(@backup_dir, URI.escape(database,/[^a-zA-Z0-9._-]/)) + ".custom"
  end

  def has_postgres?
    defined? PGconn and Process.uid(0) and Etc.getpwnam("postgres")
  rescue ArgumentError
    return false
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
  # It DOES NOT chek for databases with funny charsets used in the DB name,
  # because postgres gets confuzzled too easily.
  #
  def test_postgres_dumps

    #
    # Create a DB for each charset.  Use Iconv to convert the data between our
    # default charset and the one we're testing.
    #
    @charsets.each do |charset|
      database = Iconv.conv(charset, @default_charset, @database) + " #{charset}"
      table = Iconv.conv(charset, @default_charset, @table)
      column = Iconv.conv(charset, @default_charset, @column)
      value = Iconv.conv(charset, @default_charset, @value)
    
      chuid("postgres")
      assert_nothing_raised("Failure when creating a test Postgres DB") {
        dbh = PGconn.new(:dbname => "postgres")
        dbh.set_client_encoding(charset)
        dbh.exec "CREATE DATABASE \"#{database}\" WITH TEMPLATE = template0 ENCODING '#{charset}' LC_CTYPE='C' LC_COLLATE='C';"
        dbh.finish
      }
    
      res = nil
    
      assert_nothing_raised("Failure when creating test data in Postgres DB") {
        dbh = PGconn.new(:dbname => database)
        dbh.set_client_encoding(charset)
        dbh.exec "CREATE TABLE \"#{table}\" (\"#{column}\" CHAR(20));"
        dbh.exec "INSERT INTO \"#{table}\" (\"#{column}\") VALUES ('#{value}');"
        res = dbh.exec "SELECT * FROM \"#{table}\";"
        dbh.finish
      }
      chuid("root")
      
      #
      # Make sure we've inserted the things properly
      #
      assert_equal(1, res.nfields, "postgres returned the wrong number of fields")
      assert_equal(1, res.ntuples, "postgres returned the wrong number of tuples")
      assert_equal(column, res.fields[0], "postgres returned the wrong field name")
      assert_equal(value, res.getvalue(0,0).strip, "postgres returned the wrong value")
    
      system(@backup_script, Iconv.conv(@default_charset,charset,database))
      assert_equal(0, $?, "#{@backup_script} returned a non-zero exit code when dumping db.")
   
      drop_db(database, charset)
      dump_name = calculate_dump_name(database)
    
      chuid("postgres")
      system("pg_restore -C -d postgres #{dump_name}")
      assert_equal(0, $?, "pg_restore returned a non-zero exit code when restoring dumped db.")

      res = nil 
      assert_nothing_raised("Failure when testing restored postgres test DB") {
        dbh = PGconn.new(:dbname => database)
        dbh.set_client_encoding(charset)
        res = dbh.exec "SELECT * FROM \"#{table}\";"
        dbh.finish
      }
      chuid("root")
    
      #
      # Make sure we've inserted the things properly
      #
      assert_equal(1, res.nfields, "postgres returned the wrong number of fields")
      assert_equal(1, res.ntuples, "postgres returned the wrong number of tuples")
      assert_equal(column, res.fields[0], "postgres returned the wrong field name")
      assert_equal(value, res.getvalue(0,0).strip, "postgres returned the wrong value")
    
    end
    
  end
    
end
    
