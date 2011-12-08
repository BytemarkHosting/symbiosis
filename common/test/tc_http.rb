#!/usr/bin/ruby
#
#  Simple HTTP tests
#
#


require 'symbiosis/test/http'
require 'socket'
require 'test/unit'

class TestHTTP < Test::Unit::TestCase

  def setup
    #
    #  Create the domain
    #
    @domain = Symbiosis::Test::Http.new()
    @domain.create()

    #
    #  Create /index.html + /index.php
    @domain.setup_http()
    @domain.create_php()

  end

  def teardown
    #
    #  Delete the temporary domain
    #
    @domain.destroy()
  end

  #
  # We need this because our copy of Apache explicitly listens on the
  # external IP address.
  #
  def IP()
    ip=""
    `ifconfig eth0 | grep 'inet addr:'`.split("\n").each do |line|
      if ( /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/i.match( line ) )
        ip=$1 + "." + $2 + "." + $3 + "." + $4
      end
    end
    ip
  end

  def getCode( path, dname )
    result=nil
    sock = TCPSocket.new("#{IP()}", "80")
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
    sock = TCPSocket.new("#{IP()}", "80")
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
      assert( getCode( "/index.php", @domain.name) == "200",
              "Fetching /index.php worked" )
      assert( getCode( "/index.php", "www.#{@domain.name}") == "200",
              "Fetching /index.html worked with www prefix" )

      #
      #  A missing file should result in a 404.
      #
      assert( getCode( "/missing.php", @domain.name) == "404",
              "Fetching /missing.php failed as expected" )
      assert( getCode( "/missing.php", "www.#{@domain.name}") == "404",
              "Fetching /missing.php failed as expected with www prefix" )


      #
      #  Test that "phpinfo" expands to a full page of text
      #
      assert( getFullResponse( "/index.php", @domain.name ) =~ /PHP License/ ,
              "Expanding PHPInfo worked" )
      assert( getFullResponse( "/index.php", "www.#{@domain.name}" ) =~ /PHP License/ ,
              "Expanding PHPInfo worked with www prefix" )
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
      assert( getCode( "/index.html", @domain.name) == "200",
              "Fetching /index.html worked" )
      assert( getCode( "/index.html", "www.#{@domain.name}") == "200",
              "Fetching /index.html worked with www. prefix" )

      #
      #  Missing file.
      #
      assert( getCode( "/missing.html", @domain.name) == "404",
              "Fetching /missing.html gave the correct error" )
      assert( getCode( "/missing.html", "www.#{@domain.name}") == "404",
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

      assert( getCode( "/cgi-bin/test.cgi", @domain.name) == "500",
              "Fetching /cgi-bin/test.cgi failed as expected" )

      assert( getCode( "/cgi-bin/test.cgi", "www.#{@domain.name}" ) == "500",
              "Fetching /cgi-bin/test.cgi failed as expected with www prefix" )


      #
      #  Missing CGI
      #
      assert( getCode( "/cgi-bin/not.cgi", @domain.name) == "404",
              "Fetching /cgi-bin/not.cgi failed as expected" )

      assert( getCode( "/cgi-bin/not.cgi", "www.#{@domain.name}" ) == "404",
              "Fetching /cgi-bin/not.cgi failed as expected with www prefix" )


      #
      #  Mark it executable so that it works
      #
      @domain.setup_cgi()

      assert( getCode( "/cgi-bin/test.cgi", @domain.name) == "200",
              "Fetching /cgi-bin/test.cgi worked as expected" )

      assert( getCode( "/cgi-bin/test.cgi", "www.#{@domain.name}" ) == "200",
              "Fetching /cgi-bin/test.cgi worked as expected with www prefix" )

      #
      #  Now does it have the output we expect?
      #
      assert( getFullResponse( "/cgi-bin/test.cgi", @domain.name ) =~ /load average/ ,
              "CGI executed as expected" )
      assert( getFullResponse( "/cgi-bin/test.cgi", "www.#{@domain.name}" ) =~ /load average/ ,
              "CGI executed as expected with www prefix" )

    end
  end

end
