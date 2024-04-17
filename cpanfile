requires "Compress::Raw::Zlib" => "2.048";
requires "List::Util" => "1.45";
requires "Path::Tiny" => "0.054";
requires "String::CityHash" => ">= 0.06, <= 0.10";

on 'configure' => sub {
  requires "ExtUtils::MakeMaker::CPANfile" => "0.08";
};
