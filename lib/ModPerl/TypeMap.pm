package ModPerl::TypeMap;

use strict;
use warnings FATAL => 'all';

use ModPerl::FunctionMap ();
use ModPerl::StructureMap ();
use ModPerl::MapUtil qw(list_first);

our @ISA = qw(ModPerl::MapBase);

sub new {
    my $class = shift;
    my $self = bless { INCLUDE => [] }, $class;

    $self->{function_map}  = ModPerl::FunctionMap->new,
    $self->{structure_map} = ModPerl::StructureMap->new,

    $self->get;
    $self;
}

my %special = map { $_, 1 } qw(UNDEFINED NOTIMPL CALLBACK);

sub special {
    my($self, $class) = @_;
    return $special{$class};
}

sub function_map  { shift->{function_map}->get  }
sub structure_map { shift->{structure_map}->get }

sub parse {
    my($self, $fh, $map) = @_;

    while ($fh->readline) {
        if (/E=/) {
            my %args = $self->parse_keywords($_);
            while (my($key,$val) = each %args) {
                push @{ $self->{$key} }, $val;
            }
            next;
        }

        my @aliases;
        my($type, $class) = (split /\s*\|\s*/, $_)[0,1];
        $class ||= 'UNDEFINED';

        if ($type =~ s/^struct\s+(.*)/$1/) {
            push @aliases,
              $type, "$type *", "const $type *",
              "struct $type *", "const struct $type *",
              "$type **";

            my $cname = $class;
            if ($cname =~ s/::/__/) {
                push @{ $self->{typedefs} }, [$type, $cname];
            }
        }
        elsif ($type =~ /_t$/) {
            push @aliases, $type, "$type *", "const $type *";
        }
        else {
            push @aliases, $type;
        }

        for (@aliases) {
            $map->{$_} = $class;
        }
    }
}

sub get {
    my $self = shift;

    $self->{map} ||= $self->parse_map_files;
}

my $ignore = join '|', qw{
ap_LINK ap_HOOK _ UINT union._
union.block_hdr cleanup process_chain
iovec struct.rlimit Sigfunc in_addr_t
};

sub should_ignore {
    my($self, $type) = @_;
    return 1 if $type =~ /^($ignore)/o;
}

sub is_callback {
    my($self, $type) = @_;
    return 1 if $type =~ /\(/ and $type =~ /\)/; #XXX: callback
}

sub exists {
    my($self, $type) = @_;

    return 1 if $self->is_callback($type) || $self->should_ignore($type);

    $type =~ s/\[\d+\]$//; #char foo[64]

    return exists $self->get->{$type};
}

sub map_type {
    my($self, $type) = @_;
    my $class = $self->get->{$type};

    return unless $class and ! $self->special($class);
#    return if $type =~ /\*\*$/; #XXX
    if ($class =~ /::/) {
        return $class;
    }
    else {
        return $type;
    }
}

sub null_type {
    my($self, $type) = @_;
    my $class = $self->get->{$type};

    if ($class =~ /^[INU]V/) {
        return '0';
    }
    else {
        return 'NULL';
    }
}

sub can_map {
    my $self = shift;
    my $map = shift;

    return 1 if $map->{argspec};

    for (@_) {
        return unless $self->map_type($_);
    }

    return 1;
}

sub map_arg {
    my($self, $arg) = @_;
    return {
       name    => $arg->{name},
       default => $arg->{default},
       type    => $self->map_type($arg->{type}),
       rtype   => $arg->{type},
    }
}

sub map_args {
    my($self, $func) = @_;

    my $entry = $self->function_map->{ $func->{name} };
    my $argspec = $entry->{argspec};
    my $args = [];

    if ($argspec) {
        $entry->{orig_args} = [ map $_->{name}, @{ $func->{args} } ];

        for my $arg (@$argspec) {
            my $default;
            ($arg, $default) = split /=/, $arg, 2;
            my($type, $name) = split ':', $arg, 2;

            if ($type and $name) {
                push @$args, {
                   name => $name,
                   type => $type,
                   default => $default,
                };
            }
            else {
                my $e = list_first { $_->{name} eq $arg } @{ $func->{args} };
                if ($e) {
                    push @$args, { %$e, default => $default };
                }
                elsif ($arg eq '...') {
                    push @$args, { name => '...', type => 'SV *' };
                }
                else {
                    warn "bad argspec: $func->{name} ($arg)\n";
                }
            }
        }
    }
    else {
        $args = $func->{args};
    }

    return [ map $self->map_arg($_), @$args ]
}

sub map_function {
    my($self, $func) = @_;

    my $map = $self->function_map->{ $func->{name} };
    return unless $map;

    return unless $self->can_map($map, $func->{return_type},
                                 map $_->{type}, @{ $func->{args} });
    my $mf = {
       name        => $func->{name},
       return_type => $self->map_type($map->{return_type} ||
                                      $func->{return_type}),
       args        => $self->map_args($func),
       perl_name   => $map->{name},
    };

    for (qw(dispatch argspec orig_args prefix)) {
        $mf->{$_} = $map->{$_};
    }

    $mf->{class}  = $map->{class}  || $self->first_class($mf);
    $mf->{module} = $map->{module} || $mf->{class};

    $mf;
}

sub map_structure {
    my($self, $struct) = @_;

    my($class, @elts);
    my $stype = $struct->{type};

    return unless $class = $self->map_type($stype);

    for my $e (@{ $struct->{elts} }) {
        my($name, $type) = ($e->{name}, $e->{type});
        my $rtype;

        next unless $self->structure_map->{$stype}->{$name};
        next unless $rtype = $self->map_type($type);

        push @elts, {
           name    => $name,
           type    => $rtype,
           default => $self->null_type($type),
           pool    => $self->class_pool($class),
           class   => $self->{map}->{$type} || "",
        };
    }

    return {
       module => $self->{structure_map}->{MODULES}->{$stype} || $class,
       class  => $class,
       type   => $stype,
       elts   => \@elts,
    };
}

sub destructor {
    my($self, $prefix) = @_;
    $self->function_map->{$prefix . 'DESTROY'};
}

sub first_class {
    my($self, $func) = @_;

    for my $e (@{ $func->{args} }) {
        return $e->{type} if $e->{type} =~ /::/;
    }

    return $func->{name} =~ /^apr_/ ? 'APR' : 'Apache';
}

sub check {
    my $self = shift;

    my(@types, @missing, %seen);

    require Apache::StructureTable;
    for my $entry (@$Apache::StructureTable) {
        push @types, map $_->{type}, @{ $entry->{elts} };
    }

    for my $entry (@$Apache::FunctionTable) {
        push @types, grep { not $seen{$_}++ }
          ($entry->{return_type},
           map $_->{type}, @{ $entry->{args} })
    }

    #printf "%d types\n", scalar @types;

    for my $type (@types) {
        push @missing, $type unless $self->exists($type);
    }

    return @missing ? \@missing : undef;
}

#look for Apache/APR structures that do not exist in structure.map
my %ignore_check = map { $_,1 } qw{
module_struct cmd_how kill_conditions
regex_t regmatch_t pthread_mutex_t
unsigned void va_list ... iovec char int long const
gid_t uid_t time_t pid_t size_t
sockaddr hostent
SV
};

sub check_exists {
    my $self = shift;

    my %structures = map { $_->{type}, 1 } @{ $self->structure_table() };
    my @missing = ();
    my %seen;

    for my $name (keys %{ $self->{map} }) {
        1 while $name =~ s/^\w+\s+(\w+)/$1/;
        $name =~ s/\s+\**.*$//;
        next if $seen{$name}++ or $structures{$name} or $ignore_check{$name};
        push @missing, $name;
    }

    return @missing ? \@missing : undef;
}

#XXX: generate this
my %class_pools = (
    'Apache::RequestRec' => '.pool',
    'Apache::Connection' => '.pool',
);

sub class_pool : lvalue {
    my($self, $class) = @_;
    $class_pools{$class};
}

#anything needed that mod_perl.h does not already include
#XXX: .maps should INCLUDE= these
my @includes = qw{
apr_uuid.h
apr_sha1.h
apr_md5.h
apr_base64.h
apr_getopt.h
apr_hash.h
apr_lib.h
apr_general.h
apr_signal.h
util_script.h
util_date.h
};

sub h_wrap {
    my($self, $file, $code) = @_;

    $file = 'modperl_xs_' . $file;

    my $h_def = uc "${file}_h";
    my $preamble = "\#ifndef $h_def\n\#define $h_def\n\n";
    my $postamble = "\n\#endif /* $h_def */\n";

    return ("$file.h", $preamble . $code . $postamble);
}

sub typedefs_code {
    my $self = shift;
    my $map = $self->get;
    my %seen;

    my $file = 'modperl_xs_typedefs';
    my $h_def = uc "${file}_h";
    my $code = "";

    for (@includes, @{ $self->{INCLUDE} }) {
        $code .= qq{\#include "$_"\n}
    }

    for my $t (@{ $self->{typedefs} }) {
        next if $seen{ $t->[1] }++;
        $code .= "typedef $t->[0] * $t->[1];\n";
    }

    $self->h_wrap('typedefs', $code);
}

my %convert_alias = (
    Apache__RequestRec => 'r',
    Apache__Server => 'server',
    Apache__Connection => 'connection',
    APR__UUID => 'uuid',
    apr_status_t => 'status',
);

sub sv_convert_code {
    my $self = shift;
    my $map = $self->get;
    my %seen;
    my $code = "";

    while (my($ctype, $ptype) = each %$map) {
        next if $self->special($ptype);
        next if $ctype =~ /\s/;
        my $class = $ptype;

        if ($ptype =~ s/:/_/g) {
            next if $seen{$ptype}++;

            my $alias;
            my $expect = "expecting an $class derived object";
            my $croak  = "argument is not a blessed reference";

            #Perl -> C
            my $define = "mp_xs_sv2_$ptype";

            $code .= <<EOF;
#define $define(sv) \\
((SvROK(sv) && (SvTYPE(SvRV(sv)) == SVt_PVMG)) \\
|| (Perl_croak(aTHX_ "$croak ($expect)"),0) ? \\
($ctype *)SvIV((SV*)SvRV(sv)) : ($ctype *)NULL)

EOF

            if ($alias = $convert_alias{$ptype}) {
                $code .= "#define mp_xs_sv2_$alias $define\n\n";
            }

            #C -> Perl
            $define = "mp_xs_${ptype}_2obj";

            $code .= <<EOF;
#define $define(ptr) \\
sv_setref_pv(sv_newmortal(), "$class", (void*)ptr)

EOF

            if ($alias) {
                $code .= "#define mp_xs_${alias}_2obj $define\n\n";
            }
        }
        else {
            if ($ptype =~ /^(\wV)$/) {
                my $class = $1;
                my $define = "mp_xs_sv2_$ctype";

                $code .= "#define $define(sv) ($ctype)Sv$class(sv)\n\n";

                if (my $alias = $convert_alias{$ctype}) {
                    $code .= "#define mp_xs_sv2_$alias $define\n\n";
                }
            }
        }
    }

    $self->h_wrap('sv_convert', $code);
}

1;
__END__
