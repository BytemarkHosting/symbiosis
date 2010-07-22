
#
#  Version setup by "make" in parent directory
#

all:	mod_vhost_bytemark test


mod_vhost_bytemark:	mod_vhost_bytemark.c
	apxs2 -Wc,-Werror $(DEF) -ca mod_vhost_bytemark.c

clean:
	@find . -name '*.o' -exec rm \{\} \;
	@find . -name '*.la' -exec rm \{\} \;
	@find . -name '*.lo' -exec rm \{\} \;
	@find . -name '*.slo' -exec rm \{\} \;
	@if [ -d ./.libs ]; then rm -rf ./.libs ; fi
	@find . -name '*~' -exec rm \{\} \;
	@find . -name '.#*' -exec rm \{\} \;
	@if [ -e ./test-strip ]; then rm -f ./test-strip ; fi

test: test-strip.c
	gcc -o test-strip test-strip.c
	./test-strip

install:
	apxs2 -cia -Wc,-Werror $(DEF) mod_vhost_bytemark.c
