# Copyright 2000-2005 The Apache Software Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
package mod_perl;

use 5.006;
use strict;

BEGIN {
    our $VERSION = "1.999022";
    our $VERSION_TRIPLET;

    if ($VERSION =~ /(\d+)\.(\d\d\d)(\d+)/) {
        my $v1 = $1;
        my $v2 = int $2;
        my $v3 = int($3 . "0" x (3 - length $3));
        $VERSION_TRIPLET = "$v1.$v2.$v3";
    }
    else {
        die "bad version: $VERSION";
    }

    # $VERSION        : "1.099020"
    # int $VERSION    : 1.09902
    # $VERSION_TRIPLET: 1.99.20
}

1;
__END__

=head1 NAME

mod_perl - Embed a Perl interpreter in the Apache/2.x HTTP server

