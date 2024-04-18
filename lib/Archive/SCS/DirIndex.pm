use v5.38;
# use feature 'class';
# no warnings 'experimental::class';
use Object::Pad;

class Archive::SCS::DirIndex 0.00;

field $dirs  :param = [];
field $files :param = [];

method dirs () { $dirs->@* }
method files () { $files->@* }
