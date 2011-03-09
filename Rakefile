#!/usr/bin/ruby

require 'fileutils'
require 'rake/clean'
require 'md5'
require 'pp'

DEBEMAIL=ENV["DEBEMAIL"] || "symbiosis@bytemark.co.uk"
DEB_BUILD_ARCH=`dpkg-architecture -qDEB_BUILD_ARCH`.chomp
AVAILABLE_BUILD_ARCH=["amd64", "i386"]

CLEAN.add   %w(Release.asc Packages.new Sources.new Release.new *-stamp)
CLOBBER.add %w(Packages Sources Packages.gz Sources.gz Release Release.gpg *.deb *.tar.gz *.build *.diff.gz *.dsc *.changes)
  
DISTRO = "squeeze"

#
# Monkey patch rake to output on stdout like normal people
#
module RakeFileUtils
  # Send the message to the default rake output (which is $stderr).
  def rake_output_message(message)
    $stdout.puts(message)
  end
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

  puts "Reading packages..."

  @all_packages = Dir["*"].collect do |pkgdir|

    next unless File.exists?(pkgdir+"/debian/changelog")

    pkg = debian_version = distro = nil
    File.open(pkgdir+"/debian/changelog","r") do |fh|
      while !fh.eof? do
        fh.gets
        next unless $_ =~ /^([^ ]+) \((?:[0-9]+:)?([^\)]+)\) ([^;]+); /
        pkg, debian_version, distro = [$1, $2, $3]
        break
      end
    end

    #
    # Assume all architectures
    #
    arch = "all"
    File.open(File.join(pkgdir,"debian","control")){|fh| fh.readlines}.each do |l|
      next unless l =~ /^Architecture: (.*)/
      arch = $1 unless $1 == "all"
    end

    [pkgdir, pkg, debian_version, distro, arch]

  end.reject{|e| e.nil?}
end

def package_changess
  all_packages.collect do |pkgdir, pkg, version, distro, arch| 
    (arch == "all" ? [DEB_BUILD_ARCH] : AVAILABLE_BUILD_ARCH).collect do |this_arch|
      "#{pkg}_#{version}_#{this_arch}.changes"
    end
  end.flatten
end

def source_changess
  all_packages.collect{|pkgdir, pkg, version, distro, arch| "#{pkg}_#{version}_source.changes"}
end

def dscs
  all_packages.collect{|pkgdir, pkg, version, distro, arch| "#{pkg}_#{version}.dsc"}
end

def source_dirs
  all_packages.collect do |pkgdir, pkg, version, distro, arch|
    pkgdir
  end.uniq
end

#
# This converts a debian version into an upstream one.
#
def upstream_version(debian_version)
  raise "bad version number (#{debian_version})" unless debian_version =~ /^([0-9]+:)?([^-]+)(-.*)?$/
  $2
end

task :default => [:build]

desc "Verify integrity of packages using lintian"
task :lintian => ["lintian-stamp"]

desc "Verify package signatures"
task :verify => ["verify-stamp"] 

desc "Generate Release file"
file "Release" => ["Sources.gz", "Sources", "Packages.gz", "Packages"] do |t|
  # 
  # Standard headers
  #
  release =<<EOF
Archive: #{DISTRO}
Label: Symbiosis
Origin: Bytemark Hosting
Architectures: amd64 i386 source
Components: main
MD5Sum: 
EOF
  #
  # Add the md5sums for each prereq.
  #
  t.prerequisites.each do |prereq|
    release << " "+[ MD5.hexdigest(File.read(prereq)),
                     File.stat(prereq).size,
                     prereq].join(" ")+"\n"
  end

  File.open(t.name+".new","w+"){|fh| fh.puts release}
  FileUtils.mv("#{t.name}.new", t.name, :force => true)
end

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

desc "Generate Release.gpg"
task :build => [ "Release.gpg" ] 

desc "Generate Packages file"
file "Packages" => package_changess do |t|
  sh "dpkg-scanpackages -m . /dev/null > #{t.name}.new"
  FileUtils.mv("#{t.name}.new", t.name, :force => true)
end

desc "Generate Sources file"
file "Sources" => dscs + source_changess do |t| 
  sh "dpkg-scansources . /dev/null > #{t.name}.new"
  FileUtils.mv("#{t.name}.new", t.name, :force => true)
end

file "lintian-stamp" => source_changess + package_changess do |t| 
  sh "schroot -c #{DISTRO} -- lintian -X cpy -I #{t.prerequisites.join(" ")}"
  FileUtils.touch t.name
end

file "verify-stamp" => source_changess + package_changess + ["Release.gpg"] do |t| #: $(SOURCE_CHANGES) $(PACKAGE_CHANGES) Release.gpg
  t.prerequisites.each do |prereq|
    sh "gpg --verify #{prereq}"
  end
  FileUtils.touch t.name
end

namespace :debian do
  namespace :rules do
    task :clean do
      source_dirs.each do |d|
        begin
          File.chmod(0755, "#{d}/debian/rules")
          sh "cd #{d} && fakeroot debian/rules clean"
        rescue => err
          # do nothing because because this rules clean cannot be expected to
          # work for every package outside of a chroot.
        end
      end
    end
  end
end


#
# This builds the dsc, as well as the diff.gz
#
rule(/\.((tar|diff)\.gz|dsc)$/ =>
  proc do |task_name|
    task_name =~ /(.*)\.(diff\.gz|dsc)$/
    pkg, version = $1.split("_").first(2)
    Dir.glob("#{pkg}-#{upstream_version(version)}/**").select{|f| File.file?(f)} 
  end
) do |t|
  pkg, version = t.name.split("_").first(2)
  pkgdir, pkg, version, distro, target_arch = all_packages.find{|pd,pk,vr,ds,ar| pk == pkg}
  sh "dpkg-source -b #{pkgdir}"
end

#
# Since diff.gz are generated at the same time as dsc..
#
#rule ".diff.gz" => [
#  proc{|task_name| task_name.sub(/diff\.gz$/,"dsc")}
#]

#
# Rule to generate the source changes
#
rule(/_source.changes$/ => [
    proc{|task_name| task_name.sub(/_source\.changes$/,".dsc")}
 ]) do |t|
  #
  # Work out the package name and the version
  #
  pkg, version = t.name.split("_").first(2)
  pkgdir, pkg, version, distro, target_arch = all_packages.find{|pd,pk,vr,ds,ar| pk == pkg}

  #
  # Make sure we move any old changes out of the way.
  #
  FileUtils.rm_f(t.name)

  #
  # Now generate the changes, and sign.
  #
  sh "cd #{pkgdir} && dpkg-genchanges -S > ../#{t.name}"
#  sh "debsign #{t.name}"
end

#
# Rule to compile binary packages.
#
rule(/^([^_]+)_([^_]+)_(#{AVAILABLE_BUILD_ARCH.join("|")}).changes$/ => [ 
    proc{|task_name| task_name.sub(/_(#{AVAILABLE_BUILD_ARCH.join("|")}).changes$/,".dsc")} 
  ]) do |t|
  #
  # Need to have the distro and the arch:
  #
  pkg, version, arch = File.basename(t.name,'.changes').split("_")
  pkgdir, pkg, version, distro, target_arch = all_packages.find{|pd,pk,vr,ds,ar| pk == pkg and vr == version}

  #
  # Now call sbuild and debsign
  #
  sh "sbuild #{(target_arch == "all" ? "--arch-all" : "")} --nolog --arch=#{arch} --dist=#{distro} #{t.source}"
#  sh "debsign #{t.name}"
end


#
# Added all packaging tasks beneath a pkg namespace, because I think there is
# already a "rake" namespace.
#
namespace :pkg do
  source_dirs.each do |pkgdir|
    namespace pkgdir do
      these_packages = all_packages.find_all{|pd,pk,vr,ds,ar| pd == pkgdir}

      desc "Build #{pkgdir}"
      task :build => (
        these_packages.collect do |pd,pk,vr,ds,ar| 
          if ar == "all"
            ["#{pk}_#{vr}_#{DEB_BUILD_ARCH}.changes"]
          elsif ar == "any"
            AVAILABLE_BUILD_ARCH.collect{|a| "#{pk}_#{vr}_#{a}.changes"}
          end
        end.flatten
      )

    end
    desc "Build all versions of all packages"
    task :build => "pkg:#{pkgdir}:build".to_sym

  end

end

desc "Check which packages need their changelogs updating"
task "check_changelogs" do
  need_updating = []
  source_dirs.each do |d|
    ch_r = `hg log -l 1 --template '{rev}' #{d}/debian/changelog`.to_i
    d_r  = `hg log -l 1 --template '{rev}' #{d}/**`.to_i
    if ch_r < d_r
      ch_ch = `hg log -r #{ch_r} --template 'changelog: {rev}: {author|user}: {date|shortdate}'`
      d_ch =  `hg log -r #{d_r} --template 'directory: {rev}: {author|user}: {date|shortdate}'`
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


rsync_args = %w(
   --recursive 
   --partial 
   --verbose
   --copy-links
)

rsync_excludes = %w(*/ Makefile Rakefile TODO README .hgignore AUTOBUILD .hgtags)

hg_number  = `hg id -i -r tip`.chomp
htdocs_home = File.join(ENV['HOME'],"htdocs",DISTRO)

file "#{htdocs_home}/#{hg_number}/Release.gpg" => "Release.gpg"  do |t|
  cmd = %w(rsync) + rsync_args
  rsync_excludes.each do |ex|
    cmd << "--exclude '#{ex}'"
  end
  sh "#{cmd.join(" ")} --times $PWD/ #{htdocs_home}/#{hg_number}"
  rm "#{htdocs_home}/latest" if File.exists?("#{htdocs_home}/latest")
end

file "#{htdocs_home}/latest" => "#{htdocs_home}/#{hg_number}/Release.gpg" do |t|
  sh "cd #{htdocs_home} && ln -sf #{hg_number} latest" unless File.exists?("#{htdocs_home}/latest")
end

AVAILABLE_BUILD_ARCH.each do |arch|
  file "#{htdocs_home}/latest/#{arch}" => "#{htdocs_home}/latest" do |t|
    sh "cd #{t.prerequisites.first} && ln -sf . #{arch}"
  end
end 

desc "Upload packages to the local tree" 
task "upload" => AVAILABLE_BUILD_ARCH.collect{|arch| "#{htdocs_home}/latest/#{arch}"}

desc "Upload packages to mirror. !DANGER!" 
task "upload-live" => ["#{htdocs_home}/lenny"] + AVAILABLE_BUILD_ARCH.collect{|arch| "#{htdocs_home}/lenny/#{arch}"} do |t|
  sh "rsync -Pr --delete #{t.prerequisites.first}/ repo@mirroir.sh:htdocs/symbiosis/lenny/"
end

desc "Complete build cycle"
task "clean_build_and_upload" => %w(clobber build upload)

