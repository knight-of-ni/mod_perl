package ModPerl::BuildOptions;

use strict;
use warnings;

use Apache::Build ();
my $param_qr = qr([\s=]+);

use constant VERBOSE => 1;
use constant UNKNOWN_FATAL => 2;

use File::Spec;

sub init {
    my($self, $build) = @_;

    #@ARGV should override what's in .makepl_args.mod_perl2
    #but @ARGV might also override the default MP_OPTS_FILE
    #so snag that first
    parse($build, [grep { /^MP_OPTIONS_FILE/ } @ARGV]);
    parse_file($build);
    parse_argv($build);

    if ($build->{MP_DEBUG} and $build->{MP_USE_GTOP}) {
        $build->{MP_USE_GTOP} = 0 unless $build->find_dlfile('gtop');
    }

    unless ($build->{MP_USE_DSO} or $build->{MP_USE_STATIC}) {
        $build->{MP_USE_DSO} = $build->{MP_USE_STATIC} = 1;
    }

    $build->{MP_GENERATE_XS} = 1 unless exists $build->{MP_GENERATE_XS};

    # define MP_COMPAT_1X unless explicitly told to disable it
    $build->{MP_COMPAT_1X} = 1
        unless exists $build->{MP_COMPAT_1X} && !$build->{MP_COMPAT_1X};

}

sub parse {
    my($self, $lines, $opts) = @_;

    $opts = VERBOSE|UNKNOWN_FATAL unless defined $opts;
    my $table = table();
    my @unknown;
    my $continue = "";

    for (@$lines) {
        #XXX: this "parser" should be more robust
        chomp;
        s/^\s+//; s/\s+$//;
        next if /^\#/ || /^$/;
        last if /^__END__/;

        $_ = "$continue $_" if $continue;

        #example: +"MP_CCOPTS=-Werror" if $] >= 5.007
        if (s/^\+//) {
            $_ = eval $_;
        }

        if (/^MP_/) {
            my($key, $val) = split $param_qr, $_, 2;
            $val ||= "";
            $continue = $val =~ s/\\$// ? $key : "";

            if (!$table->{$key} and $opts & UNKNOWN_FATAL) {
                my $usage = usage();
                die "Unknown Option: $key\nUsage:\n$usage";
            }

            if ($key eq 'MP_APXS') {
                $val = File::Spec->canonpath(File::Spec->rel2abs($val));
            }

            if ($key eq 'MP_AP_PREFIX') {
                $val = File::Spec->canonpath(File::Spec->rel2abs($val));

                if (Apache::Build::WIN32()) {
                    # MP_AP_PREFIX may not contain spaces
                    require Win32;
                    $val = Win32::GetShortPathName($val);
                }
            }

            if ($table->{$key}->{append}){
                $self->{$key} = join " ", grep $_, $self->{$key}, $val;
            }
            else {
                $self->{$key} = $val;
            }

            print "   $key = $val\n" if $opts & VERBOSE;
        }
        else {
            push @unknown, $_;
        }
    }

    return \@unknown;
}

sub parse_file {
    my $self = shift;

    my $fh;
    my @files = map { $_ . 'makepl_args.mod_perl2' }
      qw(./ ../ ./. ../.), "$ENV{HOME}/.";
    unshift @files, $self->{MP_OPTIONS_FILE} if $self->{MP_OPTIONS_FILE};

    for my $file (@files) {
        if (open $fh, $file) {
            $self->{MP_OPTIONS_FILE} = $file;
            last;
        }
        $fh = undef;
    }

    return unless $fh;

    print "Reading Makefile.PL args from $self->{MP_OPTIONS_FILE}\n";
    my $unknowns = parse($self, [<$fh>]);
    push @ARGV, @$unknowns if $unknowns;

    close $fh;
}

sub parse_argv {
    my $self = shift;
    return unless @ARGV;

    my @args = @ARGV;
    @ARGV = ();

    print "Reading Makefile.PL args from \@ARGV\n";
    my $unknowns = parse($self, \@args);
    push @ARGV, @$unknowns if $unknowns;
}

sub usage {
    my $table = table();
    my @opts = map { "$_ - $table->{$_}->{val}" } sort keys %$table;
    join "\n", @opts;
}

sub parse_table {
    my($fh) = @_;
    my %table;
    local $_;

    while (<$fh>) {
        chomp;
        s/^\s+//; s/\s+$//;
        next if /^\#/ || /^$/;
        last if /^__END__/;
        my($key, $append, $val) = split /\s+/, $_, 3;
        $table{'MP_' . $key} = { append => $append, val => $val };
    }

    return \%table;
}

my $Table;

sub table {
    $Table ||= parse_table(\*DATA);
}

1;

# __DATA__ format:
# key        append     description
# where:
#     key:    is the option name
#     append: is whether we want to replace a default option (0)
#             or append the arg to the option (1)
#     desc:   description for this option

__DATA__
USE_GTOP       0    Link with libgtop and enable libgtop reporting
DEBUG          0    Turning on debugging (-g -lperld) and tracing
MAINTAINER     0    Maintainer mode: DEBUG=1 -DAP_DEBUG -Wall ...
CCOPTS         1    Add to compiler flags
TRACE          0    Turn on tracing
USE_DSO        0    Build mod_perl as a dso
USE_STATIC     0    Build mod_perl static
INST_APACHE2   0    Install *.pm relative to Apache2/ directory
PROMPT_DEFAULT 0    Accept default value for all would-be prompts
OPTIONS_FILE   0    Read options from given file
STATIC_EXTS    0    Build Apache::*.xs as static extensions
APXS           0    Path to apxs
AP_PREFIX      0    Apache installation or source tree prefix
APR_CONFIG     0    Path to apr-config
XS_GLUE_DIR    1    Directories containing extension glue
INCLUDE_DIR    1    Add directories to search for header files
GENERATE_XS    0    Generate XS code based on httpd version
LIBNAME        0    Name of the modperl dso library (default is  mod_perl)
COMPAT_1X      0    Compile-time mod_perl 1.0 backcompat (default is  on)
