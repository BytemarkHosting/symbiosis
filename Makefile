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
#  Make all packages - ensuring that the output goes into the ./output
# directory.
#
all: dependencies
	mkdir -p ./output || true
	for i in */debian/; do pushd $$(dirname $$i) ; ../build-utils/mybuild ; popd ; done
	(cd output/ ; dpkg-scanpackages . /dev/null | gzip > Packages.gz)
	(cd output/ ; dpkg-scansources  . /dev/null | gzip > Sources.gz)


changelog:
	@date +%Y:%m%d-1

#
# If we're using sautobuild, then there is no need to check for dependencies
#
dependencies:
	for i in */debian/; do pushd $$(dirname $$i) ; ../build-utils/dependencies --install  ; popd ; done
	touch dependencies

#
#  Clean all auto-generated files from beneath the current directory
#
clean:
	-rm */build-stamp
	-rm */configure-stamp
	-rm -rf ./output/
	-rm -rf */debian/bytemar*/
	-rm -f */debian/files
	-rm -f */debian/*.log
	-rm bytemark-vhost[-_]*
	-rm bytemark-symbiosis[-_]*
	-rm all
	-rm -rf out/
	-rm -rf staging/
	-rm *.build
	-rm dependencies
	-rm libapache*
	-find . -name '*.bak' -delete
	-rm */*.1
	for i in */; do pushd $$i; if [ -e Makefile ]; then make clean; fi ; debuild clean ; popd; done



#
#  Run "linda" on all binary packages to test for Debian policy violations.
#
linda: all
	linda *.changes


#
#  Run "lintian" on all binary packages to test for Debian policy violations.
#
lintian: all
	lintian -c --suppress-tags 'out-of-date-standards-version,latest-debian-changelog-entry-changed-to-native' *.changes

