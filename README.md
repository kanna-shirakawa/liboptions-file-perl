# liboptions-file-perl
perl module to load, manage and writes text config files

The package provides two Perl modules:

 - Options::File
 - Options::TieFile

The first reads plain text config files in various formats, make content
available via simple functions.

The second can tie a loaded config file (or a section of) to an associative
array, for easyer use.

The loaded data can be manipulated and the content written again
to disk, updating the original file or to one different one.

# formats

Recognised formats are classical key / value config files, with some
syntax variants, eg. key = value, or key (space/tab) value, can have
sections identified by strings in square brackets. Examples of such
config files are Samba configs, or windows app INI files.

The module can use an internal, custom format, that is similar to
Samba one, but have some nice features added:

 - section inheritance: if the name of a section contains one or more
   dots, an implicit parent / child relaction is made, any definition
   made in [parent] is transparently available in [parent.child] too
   (and subsequent child levels, if any); this can be used to build
   complex default/overrides scenarios

 - key / value modifiers: make sense when used with section inheritance,
   keys can be defined prepending a modifier, like:

   - *+key* the value is appended to parent one (parent can be empty)
   - *-key* the value is used only if NOT already defined by parent

# future enanchements

Take some features, now used by other my external tools, like
*jconf* and *kusa* and integrate them directly into the File modules: 

- use other already defined values, via key reference, in values,
  with any level of recursion
- automatic load a different number of the same config file but from
  different locations (using a load path, allowing default/overrides
  at file level)
- automatic load of all files from a given directory

---

# repositories

Debian format packages, for various platforms, of the latest release
of this project are available
<a target="new" href="https://repos.kubit.ch">here</a>.

---

# note

The original projects started a lot of time ago, and I was not fluent
in english, so ... the internal comments and (*gasp!*) the manpages
are in italian only, and somewhat outdated. Hope to have time to
fix this mess.
