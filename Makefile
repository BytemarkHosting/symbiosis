#
#  Makefile for people working with the bytemark-vhost packages.
#
# Steve
# --
#
SHELL="/bin/bash"


a:
	@echo "Valid targets are:"
	@echo " "
	@echo "General:"
	@echo " "
	@echo " all     - Generate all Debian packages [source + binary]."
	@echo " clean   - Clean the generated files."
	@echo " "
	@echo "Tests:"
	@echo " "
	@echo " linda   - Run linda on the built packages."
	@echo " lintian - Run lintian on the built packages."
	@echo " "
	@echo "Misc:"
	@echo " pool    - Builds a local pool structure handy for quick tests."
	@echo " "



#
#  Make all packages.
#
all: dependencies
	for i in */; do if [ `which sautobuild` ] ; then sautobuild $$i ; else pushd $$i ; debuild --no-tgz-check -sa -us -uc ; popd ; fi ; done
	-touch all

changelog:
	 @date +%Y%m%d%H%M%S

#
# If we're using sautobuild, then there is no need to check for dependencies
#
dependencies:
	-[ `which sautobuild` ] || ./meta/dependencies
	touch dependencies

#
#  Clean all auto-generated files from beneath the current directory
#
clean:
	-rm */build-stamp
	-rm */configure-stamp
	-rm -rf */debian/bytemar*/
	-rm bytemark-vhost[-_]*
	-rm all
	-rm -rf out/
	-rm -rf staging/
	-rm *.build
	-rm dependencies
	-rm libapache*
	-find . -name '*.bak' -delete
	-rm */*.1
	for i in */; do pushd $$i; if [ -e Makefile ]; then make clean; fi ; popd; done



#
#  Run "linda" on all binary packages to test for Debian policy violations.
#
linda: all
	linda *.changes


#
#  Run "lintian" on all binary packages to test for Debian policy violations.
#
lintian: all
	lintian *.changes



#
# Create a suitable pool
#
pool: all
	[ -d out ] || mkdir out
	for i in */debian/.package ; do mv `cat $$i`_* out ; done
	dpkg-scanpackages out /dev/null | gzip > out/Packages.gz
	dpkg-scansources  out /dev/null | gzip > out/Sources.gz

#
#  Pull any changes from the remote mercurial repository.
#
update:
	hg pull --update



etch:
	hg update -C etch

lenny:
	hg update -C lenny
