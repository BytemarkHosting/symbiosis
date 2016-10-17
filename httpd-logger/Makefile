
#
# Not sure this is the correct variable to use, but it appears to give the
# right name!
#
DEB_BUILD_GNU_TYPE := $(shell dpkg-architecture -q DEB_BUILD_GNU_TYPE)

all: obj-$(DEB_BUILD_GNU_TYPE)/bin/symbiosis-httpd-logger

clean:
	$(RM) -r obj-$(DEB_BUILD_GNU_TYPE)

#
# Make sure the binary has built before running the test
#
test: obj-$(DEB_BUILD_GNU_TYPE)/bin/symbiosis-httpd-logger
	ruby -I ../common/lib/ test/tc_apache_logger.rb

#
# The dh-golang stuff seems to put the binary in obj-$DEB_BUILD_GNU_TYPE/bin
#
obj-$(DEB_BUILD_GNU_TYPE)/bin/%: %.go
	mkdir -p ${DEB_BUILD_GNU_TYPE}/bin
	go build -o $@ $<

.PHONY: test clean all
