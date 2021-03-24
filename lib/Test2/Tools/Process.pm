package Test2::Tools::Process;

use strict;
use warnings;
use Test2::API qw( context );
use base qw( Exporter );
use 5.008004;

# ABSTRACT: Unit tests for code that calls exit, exec, system or qx()
# VERSION

our @EXPORT = qw( exec_arrayref never_exec_ok );

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=head2 exec_arrayref

=cut

our $exec_handler = sub {
  CORE::exec(@_);
};
BEGIN {
  *CORE::GLOBAL::exec = sub { $exec_handler->(@_) };
}

my $last;

sub exec_arrayref(&)
{
  my($code) = @_;

  undef $last;

  return Test2::Tools::Process::ReturnMultiLevel::with_return(sub {
    my($return) = @_;
    local $exec_handler = sub {
      $last = [caller(1)];
      $return->([@_]);
    };
    $code->();
    undef;
  });
}

=head2 never_exec_ok

=cut

sub never_exec_ok (&;$)
{
  my($code, $name) = @_;

  $name ||= 'does not call exec';

  my $ret = exec_arrayref { $code->() };
  my $ok = !defined $ret;

  my $ctx = context();
  $ctx->ok($ok, $name);

  if(!$ok && $last)
  {
    my($package, $filename, $line) = @$last;
    $ctx->diag("exec at $filename line $line");
  }

  $ctx->release;
}

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
