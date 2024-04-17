use v5.38;
use feature 'class';
no warnings 'experimental::class';

class Archive::SCS::HashFS 0.00;

use Archive::SCS::CityHash qw(cityhash64 cityhash64_int);
use Carp 'croak';
use Compress::Raw::Zlib 2.048 qw(crc32 Z_OK Z_STREAM_END);
use Fcntl 'SEEK_SET';
# use String::CRC32 'crc32';
use List::Util 'first';

our @CARP_NOT = qw( Archive::SCS );

my $MAGIC = 'SCS#';

field $file :param;
field $fh;

field %entries;
field @dirs;
field @files;

ADJUST {
  $file isa Path::Tiny && $file->exists or croak
    "Param file must be a valid Path::Tiny object";
}

my $zlib = do {
  my %opts = ( -ConsumeInput => 0, -CRC32 => 1 );
  my ($zlib, $status) = Compress::Raw::Zlib::Inflate->new( %opts );
  $zlib or die $status;
};


method file () {
  $file
}


sub handles_file ($class, $fh, $header) {
  ! -d $fh && $header =~ /^\Q$MAGIC\E\x01\x00/
}


method mount () {
  my $filename = $file->basename;
  $self->is_mounted and croak sprintf "%s: Already mounted", $filename;

  # Read HashFS file header

  open $fh, '<:raw', $file or croak "$filename: $!";
  my $success = read $fh, my $header, 20;
  $success and $MAGIC eq substr $header, 0, 4 or croak
    "$filename: Not an SCS HashFS archive";

  my ($version, $salt, $hash_method, $entry_count, $start)
    = unpack 'vv A4 VV', substr $header, 4;

  $version == 1 or croak
    "$filename: HashFS version $version unsupported";
  $salt == 0 or croak
    "$filename: HashFS salt unsupported";
  $hash_method eq 'CITY' or croak
    "$filename: HashFS hash method '$hash_method' unsupported";

  print STDERR sprintf "%s: ", $filename;

  # Read HashFS entry headers

  my $header_template = '(QQLLLL)<';
  my $header_length = length pack $header_template;
  seek $fh, $start, SEEK_SET;

  for my $i ( 0 .. $entry_count - 1 ) {
    read $fh, my $header, $header_length or die
      "$!" || "Unexpected EOF reading entry header $i";
    my %entry;
    (
      $entry{hash},
      $entry{offset},
      $entry{flags},
      $entry{crc},
      $entry{size},
      $entry{zsize}, # compressed size
    ) = unpack $header_template, $header;

    # Read known flags
    $entry{is_dir}        = $entry{flags} & 0x1;
    $entry{is_compressed} = $entry{flags} & 0x2;

    $entries{ cityhash64_int $entry{hash} } = \%entry;
  }

  return $self;
}


method unmount () {
  close $fh or croak sprintf "%s: $!", $file->basename;
  $fh = undef;
}


method is_mounted () {
  !! $fh
}


method read_dir_tree (@roots) {
  my $root = first { exists $entries{ cityhash64 $_ } } @roots;
  defined $root or return;

  @dirs = ($root);
  @files = ();
  for (my $i = 0; $i < @dirs; ++$i) {
    my $dir = $dirs[$i];

    my $data = eval { $self->read_entry( cityhash64 $dir ) };
    defined $data or next;

    $dir .= '/' if length $dir;
    for my $item (split /\n/, $data) {
      if ('*' eq substr $item, 0, 1) {
        push @dirs, $dir . substr $item, 1;
      }
      else {
        push @files, $dir . $item;
      }
    }
  }
}


method list_dirs () {
  return @dirs;
}


method list_files () {
  return @files;
}


method read_entry ($hash) {
  $fh or croak sprintf "%s: Not mounted", $file->basename;

  my $entry = $entries{ $hash };

  seek $fh, $entry->{offset}, SEEK_SET;
  my $length = read $fh, my $data, $entry->{zsize};

  defined $length or croak
    sprintf "%s: %s", $file->basename, $!;
  $length == $entry->{zsize} or croak
    sprintf "%s: Read %i bytes, expected %i bytes",
    $file->basename, $length, $entry->{zsize};

  my $crc;
  if ($entry->{is_compressed}) {
    my $status = $zlib->inflate( \(my $raw = $data), \$data );

    $status == Z_OK || $status == Z_STREAM_END
      or warnings::warnif io =>
      sprintf "%s: Inflation failed: %s (%i)",
      $file->basename, $zlib->msg // "", $status;

    $crc = $zlib->crc32;
    $zlib->inflateReset;

    length $data == $entry->{size}
      or warnings::warnif io =>
      sprintf "%s: Inflated to %i bytes, expected %i bytes",
      $file->basename, length $data, $entry->{size};
  }
  else {
    $crc = crc32($data);
  }
  $crc == $entry->{crc}
    or warnings::warnif io =>
    sprintf "%s: Found CRC32 %08X, expected %08X",
    $file->basename, $crc, $entry->{crc};
  # The official SCS extractor doesn't seem to verify the CRC

  return $data;
}


method entries () {
  keys %entries
}


=head1 NAME

Archive::SCS::HashFS - SCS HashFS version 1 format handler

=head1 SYNOPSIS

  my $file = Path::Tiny->new('.../base.scs');
  my $archive = Archive::SCS::HashFS->new(file => $file)->mount;

  $archive->read_dir_tree;
  my @contents = sort $archive->list_dirs, $archive->list_files;

  my $hash = Archive::SCS::CityHash::cityhash64('def/city.sii');
  my $data = $archive->read_entry($hash);

=head1 DESCRIPTION

Represents an SCS archive file encoded in HashFS version 1
(basically 1.49 and earlier).

Hash values used with this module must be in the internal format
(currently, an 8-byte scalar PV in network byte order).

=head1 METHODS

=head2 entries

  $entry_hashes = $archive->entries;

=head2 file

  $path_tiny = $archive->file;

=head2 is_mounted

  $bool = $archive->is_mounted;

=head2 handles_file

  $bool = Archive::SCS::HashFS->handles_file($fh, $header);

=head2 list_dirs

  @directories = $scs->list_dirs;

=head2 list_files

  @files = $scs->list_files;

=head2 mount

  $archive = $archive->mount;

=head2 new

  $archive = Archive::SCS::HashFS->new(file => $path_tiny);

=head2 read_dir_tree

  $archive->read_dir_tree;

=head2 read_entry

  $data = $archive->read_entry($hash);

=head2 unmount

  $archive->unmount;

=head1 SEE ALSO

=over

=item * L<https://modding.scssoft.com/index.php?title=Documentation/Tools/Game_Archive_Extractor&oldid=4568>

=item * L<https://github.com/sk-zk/TruckLib/tree/master/TruckLib.HashFs>

=item * L<https://github.com/truckermudgeon/maps/tree/main/packages/clis/parser/game-files>

=item * L<https://forum.scssoft.com/viewtopic.php?p=644638#p644638>

=item * L<https://forum.scssoft.com/viewtopic.php?p=1233222#p1233222>

=item * L<https://forum.scssoft.com/viewtopic.php?t=248485>

=back

=head1 AUTHOR

L<nautofon|https://github.com/nautofon>

=head1 COPYRIGHT

This software is copyright (c) 2024 by nautofon.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
