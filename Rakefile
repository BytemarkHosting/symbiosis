#!/usr/bin/ruby

require 'fileutils'
require 'rake/clean'
require 'digest'
require 'pp'

DEBEMAIL = ENV["DEBEMAIL"] || "symbiosis@bytemark.co.uk"
DEB_BUILD_ARCH = ENV["BUILD_ARCH"] || `dpkg-architecture -qDEB_BUILD_ARCH`.chomp
DISTRO   = (ENV["DISTRO"]   || "debian").downcase
RELEASE  = (ENV["RELEASE"]  || "stable").downcase
CODENAME  = (ENV["CODENAME"]  || "jessie").downcase
REPONAME = (ENV["REPONAME"] || "symbiosis").downcase
PARALLEL_BUILD = ENV.has_key?("PARALLEL_BUILD")

#
# Monkey patch rake to output on stdout like normal people
#
module RakeFileUtils
  # Send the message to the default rake output (which is $stderr).
  def rake_output_message(message)
    $stdout.puts(message)
  end
end

def has_sautobuild?
  return @has_sautobuild if defined? @has_sautobuild
  @has_sautobuild = ( !ENV.has_key?("NO_SAUTOBUILD") and File.executable?("/usr/bin/sautobuild") )
end

def available_build_archs
  return @available_build_archs if defined? @available_build_archs

  if has_sautobuild?
    chroots = `/usr/bin/schroot -l`.to_s.split
    return (@available_build_archs = [DEB_BUILD_ARCH]) unless 0 == $?
  else
    return (@available_build_archs = [DEB_BUILD_ARCH])
  end

  archs = chroots.collect do |chroot|
    if chroot =~ /^(?:chroot:)?#{DISTRO}_#{RELEASE}-([a-z0-9]+)$/i
      $1
    else
      nil
    end
  end.compact.sort.uniq

  if archs.empty?
    warn "Could not find any schroots for the #{DISTRO} #{RELEASE}.  Not using sautobuild"
    @has_sautobuild = false
    archs = [DEB_BUILD_ARCH] 
  end

  archs -= ["source"]

  @available_build_archs = archs
end

#
# This returns a list of all packages with the following format:
#
#  [name, Debian version, distro, architecture]
#
def all_packages
  #
  # Cache the answer, since this is a costly question.
  #
  return @all_packages unless @all_packages.nil?

  @all_packages = Dir["*"].collect do |pkgdir|

    next unless File.exist?(pkgdir+"/debian/changelog")

    bin_pkgs = []
    source = pkg = arch = version = distro = nil
    arch_dependent = false

    File.open(pkgdir+"/debian/changelog","r") do |fh|
      while !fh.eof? do
        fh.gets
        next unless $_ =~ /^([^ ]+) \((?:[0-9]+:)?([^\)]+)\) ([^;]+); /
        source, version, distro = [$1, $2, $3]
        break
      end
    end

    #
    # Assume all architectures
    #
    bin_pkgs = []
    arch = "all"
    File.open(File.join(pkgdir,"debian","control")){|fh| fh.readlines}.each do |l|
      case l
        when /^Package: (.*)/
          pkg = $1
        when /^Architecture: (.*)/
          this_arch = $1
          arch_dependent = (arch_dependent or this_arch != "all")
          (this_arch == "any" ? available_build_archs : %w(all)).collect do |a|
            bin_pkgs << "#{pkg}_#{version}_#{a}.deb"
          end
          pkg = nil
      end
    end

    source_version = "#{source}_#{version}"

    {:dir => pkgdir,
     :source => source,
     :source_changes => "#{source_version}_source.changes",
     :changes => (arch_dependent ? available_build_archs : [DEB_BUILD_ARCH]).collect do |this_arch|
        "#{source_version}_#{this_arch}.changes"
     end,
     :builds => (arch_dependent ? available_build_archs : [DEB_BUILD_ARCH]).collect do |this_arch|
        "#{source_version}_#{this_arch}.build"
     end,
     :packages => bin_pkgs,
     :version => version,
     :distro  => distro,
     :targz   => source_version+".tar.gz",
     :diffgz  => source_version+".diff.gz",
     :dsc     => source_version+".dsc",
     :arch_dependent => arch_dependent }
  end.compact
end

def package_changess(source = nil)
  all_packages.select do |pkg| 
    source.nil? or pkg[:source] == source
  end.collect { |pkg| pkg[:changes] }.flatten
end

def source_changess(source = nil)
  all_packages.select do |pkg|
    source.nil? or pkg[:source] == source
  end.collect{|pkg| pkg[:source_changes] }
end

def dscs(source = nil)
  all_packages.select do |pkg|
    source.nil? or pkg[:source] == source
  end.collect{|pkg| pkg[:dsc] }
end

def source_dirs(source= nil)
  all_packages.select do |pkg|
    source.nil? or pkg[:source] == source
  end.collect{|pkg| pkg[:dir] }
end

def packages(source = nil)
  all_packages.select do |pkg|
    source.nil? or pkg[:source] == source
  end.collect{|pkg| pkg[:packages] }.flatten
end

def targzs(source = nil)
  all_packages.select do |pkg|
    source.nil? or pkg[:source] == source
  end.collect{|pkg| pkg[:targz] }
end

def builds(source = nil)
  all_packages.select do |pkg|
    source.nil? or pkg[:source] == source
  end.collect{|pkg| pkg[:builds] }.flatten
end

def find_package_by_filename(fn)
  return nil unless fn =~ /\./

  all_packages.find do |pkg|
    pkg.values.any? do |val|
      (val.is_a?(Array) ?  val.include?(fn) : val == fn)
    end
  end
end

#
# This converts a debian version into an upstream one.
#
def upstream_version(debian_version)
  raise "bad version number (#{debian_version})" unless debian_version =~ /^([0-9]+:)?([^-]+)(-.*)?$/
  $2
end

#
# Works out the mercurial identity for the current RCS repo.
#
def git_id
  return @git_id if defined? @git_id

  @git_id = `git log -n 1 --format=%h`.chomp
  @git_id = nil if 0 != $?
  @git_id
end

#
# Returns the name of the repository directory.
#
def repo_dir 
  if git_id.nil?
    File.join("repo", distro)
  else
    File.join("repo", git_id)
  end
end

#####################################################################
#
# TASKS
#
#####################################################################

# The default task if nothing is specified
task :default => "Release"

#
# Generate the Release file
#
file "Release" => ["Sources.gz", "Sources", "Packages.gz", "Packages"] do |t|
  require 'socket'

  # 
  # Standard headers
  #
  release =<<EOF
Description: Bytemark Symbiosis, built for #{DISTRO.capitalize} #{RELEASE}
Origin: Bytemark Hosting
Label: #{REPONAME}
Suite: #{RELEASE}
Codename: #{CODENAME}
Architectures: #{available_build_archs.join(" ")} source
EOF
  #
  # Add the md5sums for each prereq.
  #
  hashes = Hash.new{|h,k| h[k] = []}
  t.prerequisites.each do |prereq|
    data = File.read(prereq)
    size = File.stat(prereq).size
    [Digest::MD5, Digest::SHA1, Digest::SHA256].each do |klass|
      hashes[klass] << [klass.hexdigest(data), size, prereq]
    end
  end
  release << "MD5Sum: \n " + hashes[Digest::MD5].collect{|m| m.join(" ")}.join("\n ")+"\n"
  release << "SHA1: \n "   + hashes[Digest::SHA1].collect{|m| m.join(" ")}.join("\n ")+"\n"
  release << "SHA256: \n " + hashes[Digest::SHA256].collect{|m| m.join(" ")}.join("\n ")+"\n"

  File.open(t.name+".new","w+"){|fh| fh.puts release}
  FileUtils.mv("#{t.name}.new", t.name, :force => true)
end

#
# Generate the Packages file
#

file "Packages" => [(PARALLEL_BUILD ? "pkg:parallel:all" : "pkg:all" )] do |t|
  sh "dpkg-scanpackages -m . /dev/null > #{t.name}.new"
  FileUtils.mv("#{t.name}.new", t.name, :force => true)
end

#
# Generate the Sources file
#
file "Sources" => [(PARALLEL_BUILD ? "pkg:parallel:genchanges" : "pkg:genchanges" )] do |t|
  sh "dpkg-scansources . /dev/null > #{t.name}.new"
  FileUtils.mv("#{t.name}.new", t.name, :force => true)
end

desc "Sign the repository"
task :sign  => ["all", "Release.gpg" ] 

desc "Build all packages and documentation"
task :all   => ["Release"]

desc "Check all build dependencies."
task :dependencies  => "pkg:dependencies" 

desc "Remove any temporary products."
task :clean => "pkg:clean" do
 rm_f  %w(Release.asc Packages.new Sources.new Release.new *-stamp)
end

desc "Remove any generated file."
task :clobber => %w(clean pkg:clobber) do
 rm_f %w(Packages Sources Packages.gz Sources.gz Release Release.gpg)
end

desc "Verify integrity of packages using lintian"
task :lintian => ["lintian-stamp"]

file "lintian-stamp" => source_changess + package_changess do |t| 
  if has_sautobuild?
    sh "schroot -c #{DISTRO}_#{RELEASE} -- lintian -X cpy -I #{t.prerequisites.join(" ")}"
  else
    sh "lintian -X cpy -I #{t.prerequisites.join(" ")}"
  end
  FileUtils.touch t.name
end

desc "Verify package signatures"
task :verify => ["verify-stamp"] 

file "verify-stamp" => source_changess + packages + ["Release.gpg"] do |t| 
  t.prerequisites.each do |prereq|
    sh "gpg --verify #{prereq}"
  end
  FileUtils.touch t.name
end


desc "Check which packages need their changelogs updating"
task "check_changelogs" do
  need_updating = []
  br = `git branch`.split($/).find{|b| b =~ /^\* /}.sub(/^\* +/,"")
  source_dirs.each do |d|
    ch_t = `git log -n 1 --format='%at' #{br} #{d}/debian/changelog`.to_i
    d_t  = `git log -n 1 --format='%at' #{br} #{d}/**`.to_i
    if ch_t < d_t
      ch_ch = `git log -n 1 --format='changelog: %h: %an: %ai' #{br} #{d}/debian/changelog`.chomp
      d_ch =  `git log -n 1 --format='directory: %h: %an: %ai' #{br} #{d}/**`.chomp
      need_updating << d + "\n    " + ch_ch + "\n    " + d_ch
    end
  end

  if need_updating.length > 0
    puts "The following packages _probably_ need new changelog entries:"
    puts " * "+need_updating.join("\n * ")
    puts "Note that this is only a very rough check!"
  else
    puts "All package changelogs are up-to-date."
  end
end

desc "Build a repository suitable for testing."
task "repo" => "Release" do
  mkdir_p repo_dir
  cp packages, repo_dir
  cp targzs, repo_dir
  cp source_changess, repo_dir
  cp package_changess, repo_dir
  cp dscs, repo_dir
  cp builds, repo_dir
  cp %w(Release Sources.gz Sources Packages.gz Packages), repo_dir
end

desc "Generate API documentation."
task "rdoc" => "doc/html/created.rid"

#
# This rule makes sure the docs are rebuild if there is a change to any of the
# ruby code.
#
rule("doc/html/created.rid" => 
  proc do
    source_files = Dir.glob(File.join("*","lib","**","*")).select{|f| File.file?(f)}
    source_files += Dir.glob(File.join("*","ext","**","*")).select{|f| File.file?(f)}
    source_files
  end
) do
  Rake::Task["rdoc:all"].invoke
end

namespace :rdoc do

  #
  # Build all the documentation, removing any existing.
  #
  task :all => ["dependencies", "clobber"] do
    sh "rdoc --diagram --op doc/html */lib/ */ext/"
  end

  #
  # Make sure we've got the correct dependencies for building rdoc.
  #
  task :dependencies do 
    missing_build_deps = []
    [
      %w(/usr/bin/rdoc rdoc),
      %w(/usr/bin/dot graphviz)
    ].each do |executable, package|
      missing_build_deps << package unless File.executable?(executable)
    end
  
    raise "Need to install the following packages to build documentation:\n  #{missing_build_deps.join(" ")}" unless missing_build_deps.empty?
  end 

  task :clean do
    # no op
  end
  
  task :clobber do
    rm_rf "doc/html"
  end

end

desc "Upload packages to the local tree" 
task "upload" => "repo" do
  #
  # TODO
  #
end


#
# Create a namespace for all the packaging tasks
#
namespace :pkg do

  #
  # Create a namespace per package.
  #
  all_packages.each do |pkg|
    
    #
    # Task to build our package -- an easy to remember name
    #
    desc "Build #{pkg[:source]}"
    task pkg[:source]   => "pkg:#{pkg[:source]}:all"
    
    #
    # Add the package specific tasks to the generic build tasks -- these are
    # used in the top-level tasks.
    #
    task :all           => "pkg:#{pkg[:source]}:all"
    task :genchanges    => "pkg:#{pkg[:source]}:genchanges"
    task :source        => "pkg:#{pkg[:source]}:source"
    task :buildpackage  => "pkg:#{pkg[:source]}:buildpackage"
    task :clean         => "pkg:#{pkg[:source]}:clean"
    task :clobber       => "pkg:#{pkg[:source]}:clobber"
    task :dependencies  => "pkg:#{pkg[:source]}:dependencies"
    
    multitask "parallel:all"           => "pkg:#{pkg[:source]}:all"
    multitask "parallel:genchanges"    => "pkg:#{pkg[:source]}:genchanges"
    multitask "parallel:source"        => "pkg:#{pkg[:source]}:source"
    multitask "parallel:buildpackage"  => "pkg:#{pkg[:source]}:buildpackage"
    multitask "parallel:clean"         => "pkg:#{pkg[:source]}:clean"
    multitask "parallel:clobber"       => "pkg:#{pkg[:source]}:clobber"
    multitask "parallel:dependencies"  => "pkg:#{pkg[:source]}:dependencies"

    namespace pkg[:source] do
      
      task :source do |t|
        #
        # Make sure the documentation is build before creating the source tgz
        # for any documentation package.
        #
        Rake::Task["rdoc"].invoke if "doc" == pkg[:dir]
        sh "dpkg-source -b #{pkg[:dir]}"
      end

      task :genchanges => [pkg[:dsc]] do 
        sh "cd #{pkg[:dir]} && dpkg-genchanges -S > ../#{pkg[:source_changes]}"
      end

      task :buildpackage => ["dependencies", pkg[:dsc], pkg[:source_changes]].flatten do
        #
        # Now call sautobuild and debsign
        #
        if has_sautobuild?
          if File.exists?("#{pkg[:source]}-sources.list")
            sources_list = "--sources-list=#{pkg[:source]}-sources.list"
          else
            sources_list = ""
          end
          sh "/usr/bin/sautobuild #{sources_list} --no-repo --dist=#{DISTRO}_#{RELEASE} #{pkg[:dir]}"
        else
          sh "cd #{pkg[:dir]} && debuild -us -uc -sa"
        end
      end

      task :clean do
        Rake::Task["rdoc:clean"].invoke if "doc" == pkg[:dir]
        begin
          unless has_sautobuild?
            File.chmod(0755, "#{pkg[:dir]}/debian/rules")
            sh "cd #{pkg[:dir]} && fakeroot debian/rules clean"
          end
        rescue => err
          # do nothing because because this rules clean cannot be expected to
          # work for every package outside of a chroot.
        end
      end

      task :clobber => "clean" do
        Rake::Task["rdoc:clobber"].invoke if "doc" == pkg[:dir]

        rm_f pkg[:packages] + pkg[:builds] + pkg[:changes] + [pkg[:dsc], pkg[:targz], pkg[:diffgz], pkg[:source_changes]]
      end

      task :dependencies => [File.join(pkg[:dir],"debian","control")] do |t|
        Rake::Task["rdoc:dependencies"].invoke if "doc" == pkg[:dir]

        missing_build_deps = if has_sautobuild?
          []
        else
          pkg_depends = `cd #{pkg[:dir]} && dpkg-checkbuilddeps 2>&1`.chomp
          if 0 != $? 
            if pkg_depends =~ /^dpkg-checkbuilddeps: Unmet build dependencies: (.*)/i
              $1.gsub(/\([^\)]+\)/,'').split(" ")
            else
              raise "dpkg-checkbuilddeps returned unrecognised output:\n#{pkg_depends}"
            end
          else
            []
          end
        end

        raise "Need to install the following packages to build #{pkg[:source]}:\n  #{missing_build_deps.join(" ")}" unless missing_build_deps.empty?
      end 

      task :all  => pkg[:packages]
    end

  end

end

#####################################################################
# 
# RULES
#
#####################################################################

desc "Generic rule to create a detached signature for something."
rule '.gpg' => [ proc {|t| t.sub(/.gpg$/,"") } ] do |t|
  sh "gpg --armor --sign-with #{DEBEMAIL} --detach-sign --output - #{t.source} > #{t.name}"
end

desc "Generic rule to sign something with a cleartext signature"
rule '.asc' => [ proc {|t| t.sub(/.asc$/,"") } ] do |t|
  sh "gpg --armor --sign-with #{DEBEMAIL} --clearsign --output - #{t.source} > #{t.name}"
end

desc "Generic rule to zip things up, keeping a copy."
rule '.gz' => [ proc {|t| t.sub(/.gz$/,"") } ] do |t|
  sh "cat #{t.source} | gzip -9c > #{t.name}"
end

# dsc/targz => source
# source.changes => dsc
# deb/build/changes => source.changes

desc "Generic rule to call the :source task for a package given a filename."
rule(/^[^\/]+\.(tar\.gz|diff\.gz|dsc)$/ =>
  proc do |task_name|
    pkg = find_package_by_filename(task_name)

    if pkg.nil?
      raise "Could not find package to build for #{task_name}"
    end

    source_files = Dir.glob(File.join(pkg[:dir],"**", "*")).select{|f| File.file?(f)}
    source_files << 'doc/html/created.rid' if pkg[:dir] == "doc"

    source_files
  end
) do |t|
  pkg = find_package_by_filename(t.name)

  Rake::Task["pkg:#{pkg[:source]}:source"].invoke
end

desc "Generic rule to call the :genchanges task for a package given a filename."
rule(/^[^\/]+_source\.changes$/ =>
  proc do |task_name|
    pkg = find_package_by_filename(task_name)
    raise "Could not find package to build for #{task_name}" if pkg.nil?
    pkg[:dsc]
  end
) do |t|
  pkg = find_package_by_filename(t.name)

  Rake::Task["pkg:#{pkg[:source]}:genchanges"].invoke
end

desc "Generic rule to call the :buildpackage task for a package given a filename."
rule(/^[^\/]+(_(#{available_build_archs.join("|")})\.(build|changes)|\.deb)$/ =>
  proc do |task_name|
    pkg = find_package_by_filename(task_name)
    raise "Could not find package to build for #{task_name}" if pkg.nil?
    pkg[:source_changes]
  end  
) do |t|
  pkg = find_package_by_filename(t.name)

  Rake::Task["pkg:#{pkg[:source]}:buildpackage"].invoke
end


