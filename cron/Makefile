

#
# Set up build flags
#
CFLAGS:=$(shell dpkg-buildflags --get CFLAGS)
LDFLAGS:=$(shell dpkg-buildflags --get LDFLAGS)

all: binary man

clean:
	$(RM) wrapper/symbiosis-all-crontabs
	$(RM) man/*.man

binary: wrapper/symbiosis-all-crontabs

man: man/symbiosis-all-crontabs.man man/symbiosis-crontab.man

wrapper/symbiosis-all-crontabs:	wrapper/symbiosis-all-crontabs.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $<

%.man: %.txt
	txt2man -s 1 -t $(basename $(notdir $<)) $< | sed -e 's/\\\\fB/\\fB/' > $@

test:
	cd test && ruby -I ../lib tc_crontab.rb

.PHONY: binary clean man all test
