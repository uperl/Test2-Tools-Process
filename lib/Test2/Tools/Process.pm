package Test2::Tools::Process;

use strict;
use warnings;
use 5.008004;

# ABSTRACT: Unit tests for code that calls exit, exec, system or qx()
# VERSION

package Test2::Tools::Process::ReturnMultiLevel;

# this is forked from Return::MultiLevel (XS implementation only)
# we can remove this when it gets a maintainer again.

use Scope::Upper;
use Carp qw( confess );
use base qw( Exporter );
our @EXPORT_OK = qw( with_return );

$INC{'Test2/Tools/Process/ReturnMultiLevel.pm'} = __FILE__;

sub with_return (&)
{
  my ($f) = @_;
  my $ctx = Scope::Upper::HERE();
  my @canary =
    !$ENV{RETURN_MULTILEVEL_DEBUG}
        ? '-'
        : Carp::longmess "Original call to with_return"
  ;

  local $canary[0];
  $f->(sub {
    $canary[0]
      and confess
        $canary[0] eq '-'
          ? ""
          : "Captured stack:\n$canary[0]\n",
        "Attempt to re-enter dead call frame"
      ;
      Scope::Upper::unwind(@_, $ctx);
  })
}

1;
