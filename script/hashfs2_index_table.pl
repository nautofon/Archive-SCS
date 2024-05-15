#! /usr/bin/env perl

use v5.36;

use blib;
use Archive::SCS;
use Archive::SCS::HashFS2;
use Archive::SCS::CityHash qw(
  cityhash64
  cityhash64_int
  cityhash64_hex
  cityhash64_as_hex
);

use Getopt::Long 2.33 qw( GetOptions :config gnu_getopt no_bundling no_ignore_case );
use Path::Tiny qw( path );
use Pod::Usage qw( pod2usage );

my %opts;


sub file_header ($mount) {
  my $filename = $mount->path->basename;

  open my $fh, '<:raw', $mount->path or die "$filename: $!";
  read $fh, my $header, 0x34 or die "$filename: $!";
  my %header;
  (
    $header{magic}, $header{version}, $header{salt},
    $header{hash_method}, $header{entry_count},
    $header{size1}, $header{word_count2}, $header{size2},
    $header{start1}, $header{start2}, $header{cert_start},
  )
    = unpack 'A4 vv A4 V  VVV (QQQ)<', $header;

  $header{cert_start} == 0 || $header{cert_start} == 0x80 or warn
    sprintf "%s: unexpected cert_start = %08x", $filename, $header{cert_start};

  return \%header;
}


sub print_file_header ($mount) {
  my $header = file_header $mount;

  say sprintf '%s %s HashFS version %i',
    $header->{magic}, $header->{hash_method}, $header->{version};
  say $header->{salt} ?
    sprintf 'Salt %i', $header->{salt} : 'No salt';
  say $header->{cert_start} ?
    sprintf 'Certificate: start 0x%08x', $header->{cert_start} : 'No certificate';
  say sprintf 'Index 1: start 0x%08x, compressed size 0x%x, entry count %i',
    $header->{start1}, $header->{size1}, $header->{entry_count};
  say sprintf 'Index 2: start 0x%08x, compressed size 0x%x, word count %i',
    $header->{start2}, $header->{size2}, $header->{word_count2};
}


sub raw_index ($mount, $index) {
  my $header = file_header $mount;
  my $usize =
    $index == 1 ? $header->{entry_count} * 0x10 :
    $index == 2 ? $header->{word_count2} * 4 :
    die "no index $index";
  return $mount->_get_index( $header->{"start$index"}, $header->{"size$index"}, $usize );
}


sub print_index_table ($mount, $select_entries = undef) {
  my %index_offsets;
  my $index1 = raw_index $mount, 1;
  for ( my $offset1 = 0; $offset1 < length $index1; $offset1 += 16 ) {
    my ($hash, $offset2) = unpack 'Q< L<', substr $index1, $offset1, 12;
    $index_offsets{ cityhash64_int $hash } = [ undef, $offset1, $offset2 * 4 ];
  }

  my @entries = sort {
    $index_offsets{$a}[2] <=> $index_offsets{$b}[2]
  } $mount->entries;

  if ($select_entries) {
    my %entry_hash;
    $entry_hash{$_}++ for map {( cityhash64_hex $_, cityhash64 $_ )} @$select_entries;
    @entries = grep { $entry_hash{$_} } @entries;
  }

  say "index1  index2  offset    kind/flags  zsize   usize   hash (netwk ord)  tobj_header";
  for my $hash ( @entries ) {
    next if $opts{start} && state $start++ < $opts{start} - 1;
    last if $opts{limit} && state $limit++ > $opts{limit} - 1;

    my $e = $mount->entry_meta($hash);

    my $tobj_header = $e->{is_tobj} ?
      join ' ', unpack '(H4)4 H8', join '', map $e->{parts}[$_]{header}, 0..1 : '';
#     my ( $width, $height, $ddsformat1, $mipmapcount, $ddsformat2, $d2, )
#       = unpack '(SS SS SS HHCS)<', $e->{parts}[0]{header};
#     $width += 1;
#     $height += 1;
#     $mipmapcount and $mipmapcount += 1;
#     my ( $e1, $e2, )
#       = unpack '(SS)<', $e->{parts}[1]{header};

    say sprintf "%06x  %06x  %08x  %02x/%02x %02x%02x  %06x  %06x  %s  %s",
      $index_offsets{$hash}[1], $index_offsets{$hash}[2], $e->{offset},
      $e->{parts}[0]{kind}, $e->{flags1}, $e->{flags2}, $e->{flags3},
      $e->{zsize}, $e->{size},
      cityhash64_as_hex $hash,
      $tobj_header;
  }
}


GetOptions \%opts, qw(
  entry|e=s@
  index=i
  limit=i
  start=i
);
pod2usage -verbose => 2 if $opts{help};
pod2usage unless @ARGV == 1;

my $path = path $ARGV[0];
$path->exists or die "File '$path' doesn't exist";

my $scs = Archive::SCS->new;
my $mount = $scs->mount( Archive::SCS::HashFS2->new(path => $path) );

# print_file_header $mount; exit;


if ($opts{index}) {
  print raw_index $mount, $opts{index};
  exit;
}

print_index_table $mount, $opts{entry};


=head1 SYNOPSIS

  script/hashfs2_index_table.pl dlc_ks.scs
  script/hashfs2_index_table.pl dlc_ks.scs -e 'material/ui/dlc/dlc_ks.tobj'
  script/hashfs2_index_table.pl dlc_ks.scs --index 2 | xxd > index2.txt
