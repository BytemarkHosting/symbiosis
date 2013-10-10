#!/usr/bin/ruby
#
#  Simple HTTP tests
#
#


require 'symbiosis/domain'
require 'symbiosis/test/http'
require 'socket'
require 'test/unit'

class TestHTTP < Test::Unit::TestCase

  def setup
    #
    #  Create the domain
    #
    @domain = Symbiosis::Domain.new()
    @domain.create()

    #
    #  Create /index.html + /index.php
    @domain.setup_http()
    @domain.create_php()

    @ip = Symbiosis::Host.primary_ipv4

  end

  def teardown
    #
    #  Delete the temporary domain
    #
    @domain.destroy() unless @domain.nil?
  end

  #
  # Helper methods
  #
  def getCode( path, dname )
    result=nil
    sock = TCPSocket.new("#{@ip}", "80")
    sock.print "GET #{path} HTTP/1.1\nHost: #{dname}\nConnection: close\n\n"
    response = sock.readline
    if /^HTTP.* (\d\d\d) /.match(response)
      result=$1.dup
    end
    sock.close()
    result
  end


  #
  #  Return the Header & Body of a request
  #
  def getFullResponse( path, dname )
    result=nil
    sock = TCPSocket.new("#{@ip}", "80")
    sock.print "GET #{path} HTTP/1.0\nHost: #{@domain.name}\nConnection: close\n\n"

    body = ""
    while ( ! sock.eof? )
      sock.readline
      body += $_
    end
    sock.close()
    body
  end

  #
  # Test that PHP files work.
  #
  def test_php_index
    assert_nothing_raised("test_php_index failed") do

      #
      #  Fetching /index.php
      #
      assert_equal( "200", getCode(  "/index.php", @domain.name ),
              "Fetching /index.php did not work" )
      assert_equal( "200", getCode(  "/index.php", "www.#{@domain.name}" ),
              "Fetching /index.html did not work with www prefix" )

      #
      #  A missing file should result in a 404.
      #
      assert_equal( "404", getCode(  "/missing.php", @domain.name ),
              "Fetching /missing.php did not return 404" )
      assert_equal( "404", getCode(  "/missing.php", "www.#{@domain.name}" ),
              "Fetching /missing.php did not return 404 with www prefix" )


      #
      #  Test that "phpinfo" expands to a full page of text
      #
      assert( getFullResponse( "/index.php", @domain.name ) =~ /PHP License/ ,
              "Expanding PHPInfo did not work" )
      assert( getFullResponse( "/index.php", "www.#{@domain.name}" ) =~ /PHP License/ ,
              "Expanding PHPInfo did not work with www prefix" )
    end
  end


  #
  # Test serving of /index.html works.
  #
  def test_index
    assert_nothing_raised("test_index failed") do

      #
      #  Normal file
      #
      assert_equal( "200", getCode(  "/index.html", @domain.name ),
              "Fetching /index.html did not work" )
      assert_equal( "200", getCode(  "/index.html", "www.#{@domain.name}" ),
              "Fetching /index.html did not work with www. prefix" )

      #
      #  Missing file.
      #
      assert_equal( "404", getCode(  "/missing.html", @domain.name ),
              "Fetching /missing.html gave the correct error" )
      assert_equal( "404", getCode(  "/missing.html", "www.#{@domain.name}" ),
              "Fetching /missing.html gave the correct error with the www prefix" )
    end
  end

  #
  #  Test that CGI scripts work
  #
  def test_cgi

    assert_nothing_raised("test_cgi failed") do

      #
      #  Create the stub CGI
      #
      @domain.create_cgi

      assert_equal( "500", getCode(  "/cgi-bin/test.cgi", @domain.name ),
              "Fetching /cgi-bin/test.cgi did not return 500" )

      assert_equal( "500", getCode(  "/cgi-bin/test.cgi", "www.#{@domain.name}"  ),
              "Fetching /cgi-bin/test.cgi did not return 500 with www prefix" )


      #
      #  Missing CGI
      #
      assert_equal( "404", getCode(  "/cgi-bin/not.cgi", @domain.name ),
              "Fetching /cgi-bin/not.cgi did not return 404" )

      assert_equal( "404", getCode(  "/cgi-bin/not.cgi", "www.#{@domain.name}"  ),
              "Fetching /cgi-bin/not.cgi did not return 404 with www prefix" )


      #
      #  Mark it executable so that it works
      #
      @domain.setup_cgi()

      assert_equal( "200", getCode(  "/cgi-bin/test.cgi", @domain.name ),
              "Fetching /cgi-bin/test.cgi did not work as expected" )

      assert_equal( "200", getCode(  "/cgi-bin/test.cgi", "www.#{@domain.name}"  ),
              "Fetching /cgi-bin/test.cgi did not work as expected with www prefix" )

      #
      #  Now does it have the output we expect?
      #
      assert( getFullResponse( "/cgi-bin/test.cgi", @domain.name ) =~ /load average/ ,
              "CGI did not execute as expected" )
      assert( getFullResponse( "/cgi-bin/test.cgi", "www.#{@domain.name}" ) =~ /load average/ ,
              "CGI did not execute as expected with www prefix" )

    end
  end

end
