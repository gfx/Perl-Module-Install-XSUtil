#!perl -w

use strict;

use FindBin qw($Bin);
use File::Spec;
use lib File::Spec->join($Bin, '..', 'lib'); # use Module::Install::XSUtil

use inc::Module::Install;

all_from 'lib/Foo.pm';

use_ppport 3.19;

cc_warnings;

requires_xs 'XS::MRO::Compat' => 0.12;

cc_include_paths 'include';
cc_src_paths     'src';

install_headers;

WriteAll;
