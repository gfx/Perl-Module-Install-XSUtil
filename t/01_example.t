#!perl -w

use strict;
use Test::More;

use FindBin qw($Bin);
use File::Spec;
use Config;
use File::Find;

my $dist_dir = File::Spec->join($Bin, '..', 'example');
chdir $dist_dir or die "Cannot chdir to $dist_dir: $!";

my $make = $Config{make};

ok scalar `$^X Makefile.PL`, "$^X Makefile.PL";
is $?, 0, '... success';

ok scalar `$make`, $make;
is $?, 0, '... success';

ok scalar `$make test`, "$make test";
is $?, 0, '... success';

ok -e 'ppport.h', 'ppport.h exists';

my %h_files;

find sub{
	$h_files{$_} = File::Spec->canonpath($File::Find::name) if / \.h \z/xms;
}, qw(blib);

is scalar(keys %h_files), 3, 'two head files are installed';
ok exists $h_files{'foo.h'}, 'foo.h exists';
ok exists $h_files{'bar.h'}, 'bar.h exists';
ok exists $h_files{'baz.h'}, 'baz.h exists';

sub f2rx{
	my $f = quotemeta( File::Spec->join(@_) );
	return qr/$f/xmsi;
}

like $h_files{'foo.h'}, f2rx(qw(Foo foo.h));
like $h_files{'bar.h'}, f2rx(qw(Foo bar.h));
like $h_files{'baz.h'}, f2rx(qw(Foo foo baz.h));

ok scalar `$make realclean`, "$make realclean";
is $?, 0, '... success';

done_testing;
