#!perl -w

use strict;

use FindBin qw($Bin);
use File::Spec;
use lib File::Spec->join($Bin, '..', 'lib'); # use Module::Install::XSUtil

use inc::Module::Install;

all_from 'lib/Foo.pm';

requires_xs 'XS::MRO::Compat' => 0.12;

use_ppport 3.19;

cc_warnings;

cc_include_paths 'include';
cc_src_paths     'src';

cc_define -DFOO_OK;

install_headers;

WriteAll;
