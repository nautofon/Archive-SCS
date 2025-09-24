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


sub print_index ($mount, $index) {
  my $raw = raw_index $mount, $index;

  require Data::Hexdumper;
  Data::Hexdumper->VERSION('3.00');
  my $format = '%6a: %8S>  %d';
  $index == 1 and $format = '%6a: %Q> %L> %2S>  %d';
  $index == 2 and $format = '%6a: %4L>  %d';
  print Data::Hexdumper::hexdump( $raw, { output_format => $format } )
    =~ s{^0x(.+)  }{ lc "$1  " }egmr;
  # The byte order of this output matches the physical file, not the logical data
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

  my %names;
  $names{ cityhash64 $_ } = $_ for $mount->list_files, $mount->list_dirs;
  $names{ cityhash64 '' } = '/' if exists $names{ cityhash64 '' };

  say 'index1  index2  offset    parts   flags   zsize   usize   hash (netwk ord)  entry name';
  for my $hash ( @entries ) {
    next if $opts{start} && state $start++ < $opts{start} - 1;
    last if $opts{limit} && state $limit++ > $opts{limit} - 1;

    my $e = $mount->entry_meta($hash);

    my @parts = $e->{parts}->@*;
    my $parts =
      @parts == 1 ? sprintf '%02x    ',     $parts[0]{kind} :
      @parts == 2 ? sprintf '%02x%02x  ',   $parts[0]{kind}, $parts[1]{kind} :
      @parts == 3 ? sprintf '%02x%02x%02x', $parts[0]{kind}, $parts[1]{kind}, $parts[2]{kind} :
      @parts != 0 ? sprintf '%02x #%-2i',   $parts[0]{kind}, scalar @parts : '------';

    my $tobj_header = $e->{is_tobj} ?
      join ' ', unpack '(H4)4 H8', join '', map $e->{parts}[$_]{header}, 0..1 : '';
#     my ( $width, $height, $ddsformat1, $mipmapcount, $ddsformat2, $d2, )
#       = unpack '(SS SS SS HHCS)<', $e->{parts}[0]{header};
#     $width += 1;
#     $height += 1;
#     $mipmapcount and $mipmapcount += 1;
#     my ( $e1, $e2, )
#       = unpack '(SS)<', $e->{parts}[1]{header};

    say sprintf "%06x  %06x  %08x  %s  %02x%02x%02x  %06x  %06x  %s  %s",
      $index_offsets{$hash}[1], $index_offsets{$hash}[2], $e->{offset},
      $parts, $e->{flags1}, $e->{flags2}, $e->{flags3},
      $e->{zsize}, $e->{size},
      cityhash64_as_hex $hash,
      $names{$hash} // '';
    say ' ' x 58, 'tobj header: ', $tobj_header if $e->{is_tobj};
  }
}


GetOptions \%opts, qw(
  entry|e=s@
  grep|E=s@
  help|?
  index=i
  limit=i
  raw
  start=i
);
pod2usage -verbose => 2 if $opts{help};
pod2usage unless @ARGV == 1;

my $path = path $ARGV[0];
$path->exists or die "File '$path' doesn't exist";

my $scs = Archive::SCS->new;
my $mount = $scs->mount( Archive::SCS::HashFS2->new(path => $path) );

# print_file_header $mount; exit;


if ($opts{index} && $opts{raw}) {
  print raw_index $mount, $opts{index};
  exit;
}
if ($opts{index}) {
  print_index $mount, $opts{index};
  exit;
}


if ($opts{entry} || $opts{grep}) {
  my @entries;
  if ($opts{grep}) {
    @entries = $mount->list_files, $mount->list_dirs;
    for my $grep ( $opts{grep}->@* ) {
      @entries = grep { m/$grep/ } @entries;
    }
    @entries or warn 'No entries matched with --grep';
  }
  push @entries, ( $opts{entry} // [] )->@*;

  print_index_table $mount, \@entries;
}
else {
  print_index_table $mount;
}


=head1 SYNOPSIS

  script/hashfs2_index_table.pl dlc_ks.scs
  script/hashfs2_index_table.pl dlc_ks.scs -e 'material/ui/dlc/dlc_ks.tobj'
  script/hashfs2_index_table.pl dlc_ks.scs -E 'garden_city.*rainbow'
  script/hashfs2_index_table.pl dlc_ks.scs --index 2 > index2.txt
  script/hashfs2_index_table.pl --help

=head1 OPTIONS

=over

=item --entry, -e

Limit the output table to the given entries only. Can be given
multiple times. Accepts entry pathnames or hash values
(16-byte hex string in network byte order).

=item --grep, -E

Limit the output table to only those entries that have a pathname
matching the given regular expression. If given multiple times,
each regex further restricts the entry selection (like multiple
piped C<grep>s).

=item --help, -?

Display this manual page.

=item --index

Instead of printing the composite table, print a simple ASCII hex
view of the uncompressed index 1 or index 2. See also C<--raw>.

=item --limit

Limit the output table to at most the given number of entries.

=item --raw

Modifies C<--index> to spew the raw uncompressed binary instead of
printing the ASCII view of an index. Useful for dumping the index
into a file and viewing in your hex editor of choice, or when you
don't have L<Data::Hexdumper> installed.

=item --start

Start the output table at the entry with the given number instead
of the first entry.

=back
