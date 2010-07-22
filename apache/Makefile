

nop:
	@echo "Valid targets are (alphabetically) :"
	@echo " "
	@echo " all       - Build the module"
	@echo " install   - Build *and* install the module"
	@echo " "
	@echo " clean     - Remove bogus files."
	@echo " commit    - Commit changes, after running check."
	@echo " diff      - Run a 'cvs diff'."
	@echo " install   - Install the module"
	@echo " update    - Update from the CVS repository."
	@echo " "


.PHONY:
	@true

all:
	cd src && make

test:
	cd src && make test

clean:
	cd src && make clean
	cd ruid && make clean
	@find . -name '.*~' -exec rm \{\} \;
	@find . -name '.#*' -exec rm \{\} \;
	@find . -name 'configure-stamp' -exec rm \{\} \;
	@find . -name 'build-stamp' -exec rm \{\} \;
	@if [ -d debian/libapache2-mod-ifier ]; then rm -rf debian/libapache2-mod-ifier; fi


commit:
	cvs -z3 commit


diff:
	cvs diff --unified 2>/dev/null


install:
	cd src && make install

