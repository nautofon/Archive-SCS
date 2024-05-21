use v5.28;
use ExtUtils::MakeMaker::CPANfile;

WriteMakefile(
  ABSTRACT => 'SCS archive controller',
  AUTHOR => 'nautofon <nautofon@cpan.org>',
  EXE_FILES => [
    'script/scs_archive',
  ],
  LICENSE => 'perl_5',
  META_MERGE => {
    'dynamic_config' => 0,
    'meta-spec' => {
      version => 2,
    },
    'release_status' => 'unstable',
    'resources' => {
      repository => {
        type => 'git',
        url => 'git://github.com/nautofon/Archive-SCS.git',
        web => 'https://github.com/nautofon/Archive-SCS',
      },
    },
  },
  MIN_PERL_VERSION => '5.038',
  NAME => 'Archive::SCS',
  NO_MYMETA => 1,
  VERSION => '0.01',
  test => {
    RECURSIVE_TEST_FILES => 1,
  },
);
