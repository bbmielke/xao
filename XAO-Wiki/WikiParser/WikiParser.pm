package XAO::WikiParser;
use strict;
use warnings;

require Exporter;
require DynaLoader;

our @ISA = qw(Exporter DynaLoader);
our @EXPORT = qw();
our $VERSION = '0.01';

bootstrap XAO::WikiParser $VERSION;

1;
__END__
