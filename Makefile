# Makefile - main klabs project Makefile
#
# VERSION 1.4 (2021-10-26)
#
# note: if you modify this file, please change the version line above,
# ie appending a string like 'PATCHED BY xxx'
#
# (c) 2011-2021 Lorenzo Canovi <lorenzo.canovi@kubiclabs.com>
# for copyright see /usr/share/doc/jtools/copyright

# default target, preprocess control files
#
controls:
	ku/install.sh make_controls

build:

install: build
	DESTDIR=$(DESTDIR) ku/install.sh

clean:
	rm -rf $(DESTDIR)

doc:

mrproper: clean clean_controls

clean_controls:
	for file in `ls debian.in 2>/dev/null`; do rm -f debian/$$file; done
	[ -f ku/history ] && rm -f debian.in/changelog

# a clean debian package, use this target before exporting this project to public
debianize:
	$(MAKE) mrproper
	$(MAKE) controls
	jtdeb-clean


tar:
	@[ -f ku/maketar.sh ] && ku/maketar.sh || echo " (ku/maketar.sh not present, request ignored)"
