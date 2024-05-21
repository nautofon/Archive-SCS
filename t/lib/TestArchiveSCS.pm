use strict;
use warnings;

package TestArchiveSCS;

use Exporter 'import';
BEGIN {
  our @EXPORT = qw(
    create_hashfs1
    sample1
  );
}

use Archive::SCS;
use Archive::SCS::HashFS;
use Archive::SCS::InMemory;

sub create_hashfs1 :prototype($$) {
  my ($file, $mem) = @_;
  my $scs = Archive::SCS->new;
  $scs->mount($mem);
  Archive::SCS::HashFS::create_file($file, $scs);
  $scs->unmount($mem);
}

sub sample1 :prototype() {
  my $mem = Archive::SCS::InMemory->new;
  $mem->add_entry('ones', '1' x 100);
  $mem->add_entry('empty', '');
  $mem->add_entry('orphan', 'whats my name?');
  $mem->add_entry('', {
    dirs  => [qw( emptydir dir )],
    files => [qw( ones empty )],
  });
  $mem->add_entry('emptydir', { dirs => [], files => [] });
  $mem->add_entry('dir', { dirs => ['subdir'], files => [] });
  $mem->add_entry('dir/subdir', { dirs => [], files => ['SubDirFile'] });
  $mem->add_entry('dir/subdir/SubDirFile', 'I am in a subdirectory');
  return $mem;
}

1;
