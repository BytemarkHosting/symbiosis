

nop:
	@echo "Valid targets are (alphabetically) :"
	@echo " "
	@echo " clean     - Remove bogus files."
	@echo " docs      - Create manpages for scripts in sbin."
	@echo " "

docs: man/symbiosis-create-mass-hosting-sites.man  man/symbiosis-create-sites.man  man/symbiosis-apache-logger.man man/symbiosis-generate-stats.man man/symbiosis-rotate-logs.man

man/%.man: ./sbin/%
	[ -d man ] || mkdir man
	RUBYLIB=./lib $<  --manual | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@

clean:
	cd vhost-alias && make clean
	@find . -name '.*~' -exec rm \{\} \;
	@find . -name '.#*' -exec rm \{\} \;
	@find . -name 'configure-stamp' -exec rm \{\} \;
	@find . -name 'build-stamp' -exec rm \{\} \;
	$(RM) -r man

.PHONY: clean nop symbiosis-httpd-man
