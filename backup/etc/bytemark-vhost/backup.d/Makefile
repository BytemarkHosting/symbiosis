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
	@/bin/bash $(conf_tmp)

$(conf): $(conf_tmp)
	@mv -fb $(conf_tmp) $(conf)

clean:
	@rm -f $(conf_tmp)
	@rm -f $(conf)

.PHONY:  clean all 

.PRECIOUS: $(conf)
