package Module::Install::XSUtil;

use 5.005_03;

$VERSION = '0.26';

use Module::Install::Base;
@ISA     = qw(Module::Install::Base);

use strict;

use Config;

use File::Spec;
use File::Find;

use constant _VERBOSE => $ENV{MI_VERBOSE} ? 1 : 0;

my %ConfigureRequires = (
    # currently nothing
);

my %BuildRequires = (
    'ExtUtils::ParseXS' => 2.21, # the newer, the better
);

my %Requires = (
    'XSLoader' => 0.10, # the newer, the better
);

my %ToInstall;

sub _verbose{
    print STDERR q{# }, @_, "\n";
}

sub _xs_debugging{
    return $ENV{XS_DEBUG} || scalar( grep{ $_ eq '-g' } @ARGV );
}

sub _xs_initialize{
    my($self) = @_;

    unless($self->{xsu_initialized}){
        $self->{xsu_initialized} = 1;

        if(!$self->cc_available()){
            warn "This distribution requires a C compiler, but it's not available, stopped.\n";
            exit;
        }

        $self->configure_requires(%ConfigureRequires);
        $self->build_requires(%BuildRequires);
        $self->requires(%Requires);

        $self->makemaker_args->{OBJECT} = '$(O_FILES)';
        $self->clean_files('$(O_FILES)');
        $self->clean_files('*.stackdump') if $^O eq 'cygwin';

        if($self->_xs_debugging()){
            # override $Config{optimize}
            if(_is_msvc()){
                $self->makemaker_args->{OPTIMIZE} = '-Zi';
            }
            else{
                $self->makemaker_args->{OPTIMIZE} = '-g';
            }
            $self->cc_define('-DXS_ASSERT');
        }
    }
    return;
}

# GNU C Compiler
sub _is_gcc{
    return $Config{gccversion};
}

# Microsoft Visual C++ Compiler (cl.exe)
sub _is_msvc{
    return $Config{cc} =~ /\A cl \b /xmsi;
}

{
    my $cc_available;

    sub cc_available {
        return defined $cc_available ?
            $cc_available :
            ($cc_available = shift->can_cc())
        ;
    }

    my $want_xs;
    sub want_xs {
        my $default = @_ ? shift : 1; # you're using this module, you /must/ want XS by default
        return $want_xs if defined $want_xs;

        foreach my $arg(@ARGV){
            if($arg eq '--pp'){
                return $want_xs = 0;
            }
            elsif($arg eq '--xs'){
                return $want_xs = 1;
            }
        }
        return $want_xs = $default;
    }
}

sub use_ppport{
    my($self, $dppp_version) = @_;

    $self->_xs_initialize();

    my $filename = 'ppport.h';

    $dppp_version ||= 3.19; # the more, the better
    $self->configure_requires('Devel::PPPort' => $dppp_version);
    $self->build_requires('Devel::PPPort' => $dppp_version);

    print "Writing $filename\n";

    my $e = do{
        local $@;
        eval qq{
            use Devel::PPPort;
            Devel::PPPort::WriteFile(q{$filename});
        };
        $@;
    };
    if($e){
         print "Cannot create $filename because: $@\n";
    }

    if(-e $filename){
        $self->clean_files($filename);
        $self->cc_define('-DUSE_PPPORT');
        $self->cc_append_to_inc('.');
    }
    return;
}

sub _gccversion {
    my $res = `$Config{cc} --version`;
    my ($version) = $res =~ /\(GCC\) ([0-9.]+)/;
    return $version || 0;
}

sub cc_warnings{
    my($self) = @_;

    $self->_xs_initialize();

    if(_is_gcc()){
        # Note: MSVC++ doesn't support C99, so -Wdeclaration-after-statement helps ensure C89 specs.
        $self->cc_append_to_ccflags(qw(-Wall));

        no warnings 'numeric';
        my $gccversion = _gccversion();
        if($gccversion >= 4.0){
            $self->cc_append_to_ccflags('-Wextra -Wdeclaration-after-statement');
            if($gccversion >= 4.1){
                $self->cc_append_to_ccflags('-Wc++-compat');
            }
        }
        else{
            $self->cc_append_to_ccflags('-W -Wno-comment');
        }
    }
    elsif(_is_msvc()){
        $self->cc_append_to_ccflags('-W3');
    }
    else{
        # TODO: support other compilers
    }

    return;
}

sub c99_available {
    my($self) = @_;
    $self->_xs_initialize();

    require File::Temp;
    require File::Basename;

    my $tmpfile = File::Temp->new(SUFFIX => '.c');

    $tmpfile->print(<<'C99');
inline // a C99 keyword with C99 style comments
int test_c99() {
    int i = 0;
    i++;
    int j = i - 1; // another C99 feature: declaration after statement
    return j;
}
C99

    $tmpfile->close();

    system $Config{cc}, '-c', $tmpfile->filename;

    (my $objname = File::Basename::basename($tmpfile->filename)) =~ s/\Q.c\E$/$Config{_o}/;
    unlink $objname or warn "Cannot unlink $objname (ignored): $!";

    return $? == 0;
}

sub requires_c99 {
    my($self) = @_;
    if(!$self->c99_available) {
        warn "This distribution requires a C99 compiler, but $Config{cc} seems not to support C99, stopped.\n";
        exit;
    }
    return;
}

sub cc_append_to_inc{
    my($self, @dirs) = @_;

    $self->_xs_initialize();

    for my $dir(@dirs){
        unless(-d $dir){
            warn("'$dir' not found: $!\n");
        }

        _verbose "inc: -I$dir" if _VERBOSE;
    }

    my $mm    = $self->makemaker_args;
    my $paths = join q{ }, map{ s{\\}{\\\\}g; qq{"-I$_"} } @dirs;

    if($mm->{INC}){
        $mm->{INC} .=  q{ } . $paths;
    }
    else{
        $mm->{INC}  = $paths;
    }
    return;
}

sub cc_libs {
    my ($self, @libs) = @_;

    @libs = map{
        my($name, $dir) = ref($_) eq 'ARRAY' ? @{$_} : ($_, undef);
        my $lib;
        if(defined $dir) {
            $lib = ($dir =~ /^-/ ? qq{$dir } : qq{-L$dir });
        }
        else {
            $lib = '';
        }
        $lib .= ($name =~ /^-/ ? qq{$name} : qq{-l$name});
        _verbose "libs: $lib" if _VERBOSE;
        $lib;
    } @libs;

    $self->cc_append_to_libs( @libs );
}

sub cc_append_to_libs{
    my($self, @libs) = @_;

    $self->_xs_initialize();

    return unless @libs;

    my $libs = join q{ }, @libs;

    my $mm = $self->makemaker_args;

    if ($mm->{LIBS}){
        $mm->{LIBS} .= q{ } . $libs;
    }
    else{
        $mm->{LIBS} = $libs;
    }
    return $libs;
}

sub cc_assert_lib {
    my ($self, @dcl_args) = @_;

    if ( ! $self->{xsu_loaded_checklib} ) {
        my $loaded_lib = 0;
        foreach my $checklib qw(inc::Devel::CheckLib Devel::CheckLib) {
            eval "use $checklib 0.4";
            if (!$@) {
                $loaded_lib = 1;
                last;
            }
        }

        if (! $loaded_lib) {
            warn "Devel::CheckLib not found in inc/ nor \@INC";
            exit 0;
        }

        $self->{xsu_loaded_checklib}++;
        $self->configure_requires( "Devel::CheckLib" => "0.4" );
        $self->build_requires( "Devel::CheckLib" => "0.4" );
    }

    Devel::CheckLib::check_lib_or_exit(@dcl_args);
}

sub cc_append_to_ccflags{
    my($self, @ccflags) = @_;

    $self->_xs_initialize();

    my $mm    = $self->makemaker_args;

    $mm->{CCFLAGS} ||= $Config{ccflags};
    $mm->{CCFLAGS}  .= q{ } . join q{ }, @ccflags;
    return;
}

sub cc_define{
    my($self, @defines) = @_;

    $self->_xs_initialize();

    my $mm = $self->makemaker_args;
    if(exists $mm->{DEFINE}){
        $mm->{DEFINE} .= q{ } . join q{ }, @defines;
    }
    else{
        $mm->{DEFINE}  = join q{ }, @defines;
    }
    return;
}

sub requires_xs{
    my $self  = shift;

    return $self->requires() unless @_;

    $self->_xs_initialize();

    my %added = $self->requires(@_);
    my(@inc, @libs);

    my $rx_lib    = qr{ \. (?: lib | a) \z}xmsi;
    my $rx_dll    = qr{ \. dll          \z}xmsi; # for Cygwin

    while(my $module = each %added){
        my $mod_basedir = File::Spec->join(split /::/, $module);
        my $rx_header = qr{\A ( .+ \Q$mod_basedir\E ) .+ \. h(?:pp)?     \z}xmsi;

        SCAN_INC: foreach my $inc_dir(@INC){
            my @dirs = grep{ -e } File::Spec->join($inc_dir, 'auto', $mod_basedir), File::Spec->join($inc_dir, $mod_basedir);

            next SCAN_INC unless @dirs;

            my $n_inc = scalar @inc;
            find(sub{
                if(my($incdir) = $File::Find::name =~ $rx_header){
                    push @inc, $incdir;
                }
                elsif($File::Find::name =~ $rx_lib){
                    my($libname) = $_ =~ /\A (?:lib)? (\w+) /xmsi;
                    push @libs, [$libname, $File::Find::dir];
                }
                elsif($File::Find::name =~ $rx_dll){
                    # XXX: hack for Cygwin
                    my $mm = $self->makemaker_args;
                    $mm->{macro}->{PERL_ARCHIVE_AFTER} ||= '';
                    $mm->{macro}->{PERL_ARCHIVE_AFTER}  .= ' ' . $File::Find::name;
                }
            }, @dirs);

            if($n_inc != scalar @inc){
                last SCAN_INC;
            }
        }
    }

    my %uniq = ();
    $self->cc_append_to_inc (grep{ !$uniq{ $_ }++ } @inc);

    %uniq = ();
    $self->cc_libs(grep{ !$uniq{ $_->[0] }++ } @libs);

    return %added;
}

sub cc_src_paths{
    my($self, @dirs) = @_;

    $self->_xs_initialize();

    return unless @dirs;

    my $mm     = $self->makemaker_args;

    my $XS_ref = $mm->{XS} ||= {};
    my $C_ref  = $mm->{C}  ||= [];

    my $_obj   = $Config{_o};

    my @src_files;
    find(sub{
        if(/ \. (?: xs | c (?: c | pp | xx )? ) \z/xmsi){ # *.{xs, c, cc, cpp, cxx}
            push @src_files, $File::Find::name;
        }
    }, @dirs);

    foreach my $src_file(@src_files){
        my $c = $src_file;
        if($c =~ s/ \.xs \z/.c/xms){
            $XS_ref->{$src_file} = $c;

            _verbose "xs: $src_file" if _VERBOSE;
        }
        else{
            _verbose "c: $c" if _VERBOSE;
        }

        push @{$C_ref}, $c unless grep{ $_ eq $c } @{$C_ref};
    }

    $self->clean_files(map{
        File::Spec->catfile($_, '*.gcov'),
        File::Spec->catfile($_, '*.gcda'),
        File::Spec->catfile($_, '*.gcno'),
    } @dirs);
    $self->cc_append_to_inc('.');

    return;
}

sub cc_include_paths{
    my($self, @dirs) = @_;

    $self->_xs_initialize();

    push @{ $self->{xsu_include_paths} ||= []}, @dirs;

    my $h_map = $self->{xsu_header_map} ||= {};

    foreach my $dir(@dirs){
        my $prefix = quotemeta( File::Spec->catfile($dir, '') );
        find(sub{
            return unless / \.h(?:pp)? \z/xms;

            (my $h_file = $File::Find::name) =~ s/ \A $prefix //xms;
            $h_map->{$h_file} = $File::Find::name;
        }, $dir);
    }

    $self->cc_append_to_inc(@dirs);

    return;
}

sub install_headers{
    my $self    = shift;
    my $h_files;
    if(@_ == 0){
        $h_files = $self->{xsu_header_map} or die "install_headers: cc_include_paths not specified.\n";
    }
    elsif(@_ == 1 && ref($_[0]) eq 'HASH'){
        $h_files = $_[0];
    }
    else{
        $h_files = +{ map{ $_ => undef } @_ };
    }

    $self->_xs_initialize();

    my @not_found;
    my $h_map = $self->{xsu_header_map} || {};

    while(my($ident, $path) = each %{$h_files}){
        $path ||= $h_map->{$ident} || File::Spec->join('.', $ident);
        $path   = File::Spec->canonpath($path);

        unless($path && -e $path){
            push @not_found, $ident;
            next;
        }

        $ToInstall{$path} = File::Spec->join('$(INST_ARCHAUTODIR)', $ident);

        _verbose "install: $path as $ident" if _VERBOSE;
        my @funcs = $self->_extract_functions_from_header_file($path);
        if(@funcs){
            $self->cc_append_to_funclist(@funcs);
        }
    }

    if(@not_found){
        die "Header file(s) not found: @not_found\n";
    }

    return;
}

my $home_directory;

sub _extract_functions_from_header_file{
    my($self, $h_file) = @_;

    my @functions;

    ($home_directory) = <~> unless defined $home_directory;

    # get header file contents through cpp(1)
    my $contents = do {
        my $mm = $self->makemaker_args;

        my $cppflags = q{"-I}. File::Spec->join($Config{archlib}, 'CORE') . q{"};
        $cppflags    =~ s/~/$home_directory/g;

        $cppflags   .= ' ' . $mm->{INC} if $mm->{INC};

        $cppflags   .= ' ' . ($mm->{CCFLAGS} || $Config{ccflags});
        $cppflags   .= ' ' . $mm->{DEFINE} if $mm->{DEFINE};

        my $add_include = _is_msvc() ? '-FI' : '-include';
        $cppflags   .= ' ' . join ' ', map{ qq{$add_include "$_"} } qw(EXTERN.h perl.h XSUB.h);

        my $cppcmd = qq{$Config{cpprun} $cppflags $h_file};

        _verbose("extract functions from: $cppcmd") if _VERBOSE;
        `$cppcmd`;
    };

    unless(defined $contents){
        die "Cannot call C pre-processor ($Config{cpprun}): $! ($?)";
    }

    # remove other include file contents
    my $chfile = q/\# (?:line)? \s+ \d+ /;
    $contents =~ s{
        ^$chfile  \s+ (?!"\Q$h_file\E")
        .*?
        ^(?= $chfile)
    }{}xmsig;

    if(_VERBOSE){
        local *H;
        open H, "> $h_file.out"
            and print H $contents
            and close H;
    }

    while($contents =~ m{
            ([^\\;\s]+                # type
            \s+
            ([a-zA-Z_][a-zA-Z0-9_]*)  # function name
            \s*
            \( [^;#]* \)              # argument list
            [\w\s\(\)]*               # attributes or something
            ;)                        # end of declaration
        }xmsg){
            my $decl = $1;
            my $name = $2;

            next if $decl =~ /\b typedef \b/xms;
            next if $name =~ /^_/xms; # skip something private

            push @functions, $name;

            if(_VERBOSE){
                $decl =~ tr/\n\r\t / /s;
                $decl =~ s/ (\Q$name\E) /<$name>/xms;
                _verbose("decl: $decl");
            }
    }

    return @functions;
}


sub cc_append_to_funclist{
    my($self, @functions) = @_;

    $self->_xs_initialize();

    my $mm = $self->makemaker_args;

    push @{$mm->{FUNCLIST} ||= []}, @functions;
    $mm->{DL_FUNCS} ||= { '$(NAME)' => [] };

    return;
}


package
    MY;

# XXX: We must append to PM inside ExtUtils::MakeMaker->new().
sub init_PM{
    my $self = shift;

    $self->SUPER::init_PM(@_);

    while(my($k, $v) = each %ToInstall){
        $self->{PM}{$k} = $v;
    }
    return;
}

# append object file names to CCCMD
sub const_cccmd {
    my $self = shift;

    my $cccmd  = $self->SUPER::const_cccmd(@_);
    return q{} unless $cccmd;

    if (Module::Install::XSUtil::_is_msvc()){
        $cccmd .= ' -Fo$@';
    }
    else {
        $cccmd .= ' -o $@';
    }

    return $cccmd
}

1;
__END__

=for stopwords gfx API

=head1 NAME

Module::Install::XSUtil - Utility functions for XS modules

=head1 VERSION

This document describes Module::Install::XSUtil version 0.26.

=head1 SYNOPSIS

    # in Makefile.PL
    use inc::Module::Install;

    # Enables C compiler warnings
    cc_warnings;

    # Uses ppport.h
    # No need to include it. It's created here.
    use_ppport 3.19;


    # Sets C pre-processor macros.
    cc_define q{-DUSE_SOME_FEATURE=42};

    # Sets paths for header files
    cc_include_paths 'include'; # all the header files are in include/

    # Sets paths for source files
    cc_src_paths 'src'; # all the XS and C source files are in src/

    # Installs header files
    install_headers; # all the header files in @cc_include_paths

    # This is a special version of requires().
    # If XS::SomeFeature provides header files,
    # this will add its include paths into INC
    requies_xs 'XS::SomeFeature';


=head1 DESCRIPTION

Module::Install::XSUtil provides a set of utilities to setup distributions
which include or depend on XS module.

See L<XS::MRO::Compat> and L<Method::Cumulative> for example.

=head1 FUNCTIONS

=head2 cc_available

Returns true if a C compiler is available. YOU DO NOT NEED TO CALL
THIS FUNCTION YOURSELF: it will be called for you when this module is 
initialized, and your Makefile.PL process will exit with 0 status.
Only explicitly call if you need to do some esoteric handling when
no compiler is available (for example, when you have a pure perl alternative)

=head2 want_xs ?$default

Returns true if the user asked for the XS version or pure perl version of the
module.

Will return true if C<--xs> is explicitly specified as the argument to 
F<Makefile.PL>, and false if C<--pp> is specified. If neither is explicitly
specified, will return the value specified by C<$default>. If you do not
specify the value of C<$default>, then it will be true.

=head2 requires_xs $module => ?$version

Does C<requires()> and setup B<include paths> and B<libraries>
for what I<$module> provides.

=head2 use_ppport ?$version

Create F<ppport.h> using C<Devel::PPPort::WriteFile()>.

This command calls C<< configure_requires 'Devel::PPPort' => $version >>
and adds C<-DUSE_PPPORT> to C<MakeMaker>'s C<DEFINE>.

=head2 cc_warnings

Enables C compiler warnings.

=head2 cc_define @macros

Sets C<cpp> macros as compiler options.

=head2 cc_src_paths @source_paths

Sets source file directories which include F<*.xs> or F<*.c>.

=head2 cc_include_paths @include_paths

Sets include paths for a C compiler.

=head2 cc_libs @libs

Sets C<MakeMaker>'s C<LIBS>. If a name starts C<->, it will be interpreted as is.
Otherwise prefixed C<-l>.

e.g.:

    cc_libs -lfoo;
    cc_libs  'foo'; # ditto.
    cc_libs qw(-L/path/to/libs foo bar); # with library paths

=head2 cc_assert_lib %args

Checks if the given C library is installed via Devel::CheckLib. 
Takes exactly what Devel::CheckLib takes. Note that you must pass
the path names explicitly.

=head2 requires_c99

Checks if the C compiler supports C99 features.

=head2 install_headers ?@header_files

Declares providing header files, extracts functions from these header files,
and adds these functions to C<MakeMaker>'s C<FUNCLIST>.

If I<@header_files> are omitted, all the header files in B<include paths> will
be installed.

=head2 cc_append_to_inc @include_paths

Low level API.

=head2 cc_append_to_libs @libraries

Low level API.

=head2 cc_append_to_ccflags @ccflags

Low level API.

=head2 cc_append_to_funclist @funclist

Low level API.

=head1 OPTIONS

Under the control of this module, F<Makefile.PL> accepts C<-g> option, which
sets C<MakeMaker>'s C<OPTIMIE> C<-g> (or something like). It will disable
optimization and enable some debugging features.

=head1 DEPENDENCIES

Perl 5.5.3 or later.

=head1 NOTE

In F<Makefile.PL>, you might want to use C<author_requires>, which is
provided by C<Module::Install::AuthorReauires>, in order to tell co-developers
that they need to install this plugin.

    author_requires 'Module::Install::XSUtil';

=head1 BUGS

No bugs have been reported.

Please report any bugs or feature requests to the author.

=head1 ACKNOWLEDGEMENT

Thanks to Taro Nishino for the test reports.

Tanks to lestrrat for the suggestions and patches.

=head1 AUTHOR

Goro Fuji (gfx) E<lt>gfuji(at)cpan.orgE<gt>.

=head1 SEE ALSO

L<ExtUtils::Depends>.

L<Module::Install>.

L<Module::Install::CheckLib>.

L<Devel::CheckLib>.

L<ExtUtils::MakeMaker>.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2009-2010, Goro Fuji (gfx). Some rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
