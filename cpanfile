requires "Compress::Raw::Zlib" => "2.048";
requires "List::Util" => "1.45";
requires "Path::Tiny" => "0.119";

on 'test' => sub {
  requires "IPC::Run3" => "0";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "7.12";
  requires "ExtUtils::MakeMaker::CPANfile" => "0.08";
  requires "Path::Tiny" => "0.062";
};
