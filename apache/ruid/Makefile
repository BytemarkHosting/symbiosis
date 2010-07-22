
#
#  Version setup by "make" in parent directory
#

all:	mod_ruid


mod_ruid:	mod_ruid.c
	apxs2 -Wc,-Werror $(DEF) -Wl,-lcap -ca mod_ruid.c

clean:
	@find . -name '*.o' -exec rm \{\} \;
	@find . -name '*.la' -exec rm \{\} \;
	@find . -name '*.lo' -exec rm \{\} \;
	@find . -name '*.slo' -exec rm \{\} \;
	@if [ -d ./.libs ]; then rm -rf ./.libs ; fi
	@find . -name '*~' -exec rm \{\} \;
	@find . -name '.#*' -exec rm \{\} \;

install:
	apxs2 -cia -Wc,-Werror $(DEF) mod_ruid.c
