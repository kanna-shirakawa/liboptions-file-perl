# based on KU packages template 1.3 (2012/10)

# default, preprocess control files
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
	for file in `ls fedora.in 2>/dev/null`; do rm -f fedora/$$file; done
