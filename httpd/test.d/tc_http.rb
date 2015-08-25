#
#  Simple HTTP tests
#
#


require 'symbiosis/domain'
require 'symbiosis/domain/http'
require 'symbiosis/test/http'
require 'test/unit'
require 'net/http'
require 'uri'

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
  def getResponse(path, dname)
    response = nil

    Net::HTTP.start("#{@ip}", "80") do |http|
      request = Net::HTTP::Get.new path
      request['Host'] = dname 
      response = http.request request
    end

    return response
  end

  def getCode( path, dname )
    response = getResponse(path, dname)
    response.code 
  end


  #
  #  Return the Header & Body of a request
  #
  def getFullResponse( path, dname )
    response = getResponse(path, dname)
    response.body
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

  #
  #  Test that CGI scripts get the correct document root 
  #
  def test_document_root_in_cgibin_dir
    Symbiosis::Utils.mkdir_p(@domain.htdocs_dir)
    Symbiosis::Utils.mkdir_p(@domain.cgibin_dir)

    Symbiosis::Utils.safe_open( "#{@domain.cgibin_dir}/test.cgi", "a", {:uid => @domain.uid, :gid => @domain.gid, :mode => 0755} ) do |fh|
      fh.puts( "#!/bin/sh" )
      fh.puts( "echo \"Content-type: text/plain\\n\"" )
      fh.puts( "echo -n $DOCUMENT_ROOT" )
    end

    #
    # Do this a couple of times to make sure we didn't get lucky
    #
    2.times do
      #
      #  Now does it have the output we expect?
      #
      assert_equal(@domain.cgibin_dir, getFullResponse( "/cgi-bin/test.cgi", @domain.name ),
        "Document root set incorrectly.for scripts in public/cgi-bin for #{@domain.name}" )

      assert_equal(@domain.cgibin_dir, getFullResponse( "/cgi-bin/test.cgi", "www."+@domain.name ), 
        "Document root set incorrectly for scripts in public/cgi-bin for www.#{@domain.name}" )
    end
  end

  #
  #  Test that CGI scripts get the correct document root when placed outside the normal cgi dir. 
  #
  def test_cgi_document_root_in_other_dir

    %w(test-cgi test-cgi-bin).each do |subdir|
      #
      # Now check withe a CGI script in a different directory.
      #
      Symbiosis::Utils.mkdir_p(File.join(@domain.htdocs_dir, subdir))

      Symbiosis::Utils.safe_open( "#{@domain.htdocs_dir}/#{subdir}/test.cgi", "a", 
        {:uid => @domain.uid, :gid => @domain.gid, :mode => 0755} ) do |fh|
        fh.puts( "#!/bin/sh" )
        fh.puts( "echo \"Content-type: text/plain\\n\"" )
        fh.puts( "echo -n $DOCUMENT_ROOT" )
      end
      

      Symbiosis::Utils.safe_open( "#{@domain.htdocs_dir}/#{subdir}/.htaccess", "a", 
        {:uid => @domain.uid, :gid => @domain.gid, :mode => 0644} ) do | fh|
        fh.puts('Options +ExecCGI')
      end

      #
      # Do this a couple of times to make sure we didn't get lucky
      #
      2.times do
        assert_equal(@domain.htdocs_dir, getFullResponse( "/#{subdir}/test.cgi", @domain.name ),
          "Document root set incorrectly for scripts in public/htdocs/#{subdir} for #{@domain.name}" )

        assert_equal(@domain.htdocs_dir, getFullResponse( "/#{subdir}/test.cgi", "www."+@domain.name ),
          "Document root set incorrectly for scripts in public/htdocs/#{subdir} for www.#{@domain.name}" )
      end
    end
  end
end
