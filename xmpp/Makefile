

nop:
	@echo "Valid targets are (alphabetically) :"
	@echo " "
	@echo " clean     - Remove bogus files."
	@echo " docs      - Create manpages for scripts in sbin."
	@echo " "

docs: man/symbiosis-xmpp-configure.man

man/%.man: ./sbin/%
	[ -d man ] || mkdir man
	RUBYLIB=./lib:../common/lib $<  --manual | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@

clean:
	$(RM) -r man

.PHONY: clean nop 
