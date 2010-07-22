

nop:
	@echo "Valid targets are (alphabetically) :"
	@echo " "
	@echo " clean     - Remove bogus files."
	@echo " "


clean:
	cd vhost-alias && make clean
	cd ruid && make clean
	@find . -name '.*~' -exec rm \{\} \;
	@find . -name '.#*' -exec rm \{\} \;
	@find . -name 'configure-stamp' -exec rm \{\} \;
	@find . -name 'build-stamp' -exec rm \{\} \;

