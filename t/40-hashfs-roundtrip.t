#!perl
use strict;
use warnings;
use lib 'lib';

use Feature::Compat::Defer;
use Path::Tiny 0.119;
use Test::More;

my $f1 = Path::Tiny->tempfile('Archive-SCS-test-XXXXXX');
defer { $f1->remove; }

use Archive::SCS;
use Archive::SCS::HashFS;
use Archive::SCS::InMemory;

# Create test data

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

# Roundtrip: Write new HashFS file and read it back

my $scs = Archive::SCS->new;

$scs->mount($mem);
Archive::SCS::HashFS::create_file($f1, $scs);
$scs->unmount($mem);

$scs->mount($f1);

# Compare HashFS contents with test data

is_deeply [$scs->list_dirs], [qw(
  dir
  dir/subdir
  emptydir
)], 'dirs';

is_deeply [$scs->list_files], [qw(
  dir/subdir/SubDirFile
  empty
  ones
)], 'files';

is_deeply [$scs->list_orphans], ['4063fbd34a25e9f0'], 'orphans';

is $scs->read_entry('ones'), '1' x 100, 'ones';
is $scs->read_entry('empty'), '', 'empty';
like $scs->read_entry('dir/subdir/SubDirFile'), qr/in a subdir/, 'SubDirFile';
like $scs->read_entry('orphan'), qr/whats my name/, 'orphan';
like $scs->read_entry('4063fbd34a25e9f0'), qr/whats my name/, 'hash';

done_testing;
