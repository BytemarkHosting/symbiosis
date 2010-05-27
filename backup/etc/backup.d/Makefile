conf         := backup2l.conf
conf_tmp     := $(conf).tmp
snippets_dir := conf.d
snippets     := $(shell ls $$PWD/$(snippets_dir)/[0-9][0-9]-*.conf | sort)

all: $(conf)

$(conf_tmp): Makefile $(snippets)
	@rm -f $(conf_tmp)
	@for s in $(snippets) ; do \
	    echo "# ------------------------------------------------------------------------------" >>  $(conf_tmp)  ;\
	    echo "# $$s" >> $(conf_tmp)  ;\
	    echo "# ------------------------------------------------------------------------------" >>  $(conf_tmp)  ;\
	    echo >> $(conf_tmp)  ;\
	    cat $$s >> $(conf_tmp) ;\
	done
	@echo /usr/sbin/exim4 -bV -C $(exim4_conf_tmp) > /dev/null

$(conf): $(conf_tmp)
	@mv -fb $(conf_tmp) $(conf)

clean:
	@rm -f $(conf)

.PHONY:  clean

.PRECIOUS: $(conf)
