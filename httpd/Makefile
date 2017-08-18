
RUBYLIB := "${PWD}/lib:${PWD}/../common/lib"

nop:
	@echo "Valid targets are (alphabetically) :"
	@echo " "
	@echo " clean     - Remove bogus files."
	@echo " docs      - Create manpages for scripts in sbin."
	@echo " "

docs: man/symbiosis-httpd-configure.man  man/symbiosis-httpd-logger.man man/symbiosis-httpd-generate-stats.man man/symbiosis-httpd-rotate-logs.man

test:
	$(MAKE) -C vhost-alias test
	RUBYLIB=${RUBYLIB} ruby test.d/t*.rb

.PHONY: test clean all docs
 
man/%.txt: ./sbin/%
	[ -d man ] || mkdir man
	RUBYLIB=${RUBYLIB} $< --manual > $@
	test -s $@

man/%.man: man/%.txt
	sed -e 's/^=\+$$//' $< | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@
	test -s $@

clean:
	cd vhost-alias && make clean
	@find . -name '.*~' -exec rm \{\} \;
	@find . -name '.#*' -exec rm \{\} \;
	@find . -name 'configure-stamp' -exec rm \{\} \;
	@find . -name 'build-stamp' -exec rm \{\} \;
	$(RM) -r man

.PHONY: clean nop symbiosis-httpd-man
