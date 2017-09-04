
RUBYLIB := "${PWD}/lib:${PWD}/../common/lib"

#
# Not sure this is the correct variable to use, but it appears to give the
# right name!
#
DEB_BUILD_GNU_TYPE := $(shell dpkg-architecture -q DEB_BUILD_GNU_TYPE)

all: sbin/symbiosis-httpd-logger docs

docs: man/symbiosis-httpd-configure.man man/symbiosis-httpd-generate-stats.man man/symbiosis-httpd-rotate-logs.man man/symbiosis-httpd-logger.man

#
# The dh-golang stuff seems to put the binary in obj-$DEB_BUILD_GNU_TYPE/bin
#
obj-$(DEB_BUILD_GNU_TYPE)/bin/%: %.go
	mkdir -p ${DEB_BUILD_GNU_TYPE}/bin
	go build -o $@ $<


test: obj-$(DEB_BUILD_GNU_TYPE)/bin/symbiosis-httpd-logger
	$(MAKE) -C vhost-alias test
	RUBYLIB=${RUBYLIB} ruby test.d/t*.rb

sbin/symbiosis-httpd-logger: obj-$(DEB_BUILD_GNU_TYPE)/bin/symbiosis-httpd-logger
	cp -a $< $@

man/%.txt: ./txt/%.txt
	cp -a $< $@

man/%.txt: ./sbin/%
	[ -d man ] || mkdir man
	RUBYLIB=${RUBYLIB} $< --manual > $@
	test -s $@

man/%.man: man/%.txt
	sed -e 's/^=\+$$//' $< | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@
	test -s $@

clean:
	$(RM) -r obj-$(DEB_BUILD_GNU_TYPE)
	cd vhost-alias && make clean
	@find . -name '.*~' -exec rm \{\} \;
	@find . -name '.#*' -exec rm \{\} \;
	@find . -name 'configure-stamp' -exec rm \{\} \;
	@find . -name 'build-stamp' -exec rm \{\} \;
	$(RM) -r man
	$(RM) sbin/symbiosis-httpd-logger

.PHONY: test clean all docs
