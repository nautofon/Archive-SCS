use strict;
use warnings;

package TestArchiveSCS;

use Exporter 'import';
BEGIN {
  our @EXPORT = qw(
    scs_archive
    create_hashfs1
    sample1
    sample2
    sample_base
  );
}

use Archive::SCS;
use Archive::SCS::HashFS;
use Archive::SCS::InMemory;

use Cwd;
use IPC::Run3;
use Path::Tiny;
my @CMD = qw( perl -Ilib script/scs_archive );

sub scs_archive {
  my $old_dir = getcwd;
  chdir path(__FILE__)->parent->parent->parent;
  if (wantarray) {
    my @out;
    run3 [@CMD, @_], \undef, \@out, \@out;
    chdir $old_dir;
    chomp for @out;
    @out
  }
  else {
    my $out;
    run3 [@CMD, @_], \undef, \$out, \$out;
    chdir $old_dir;
    $out
  }
}

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

sub sample2 :prototype() {
  my $mem = Archive::SCS::InMemory->new;
  $mem->add_entry('orphan', 'not actually an orphan in this sample');
  $mem->add_entry('', { dirs  => [], files => [qw( orphan )] });
  return $mem;
}

sub sample_base :prototype() {
  my $mem = Archive::SCS::InMemory->new;
  $mem->add_entry('version.txt', '0.0.0.0');
  return $mem;
}

1;
