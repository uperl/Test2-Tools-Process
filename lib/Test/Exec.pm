package Test::Exec;

use strict;
use warnings;
use Test2::API qw( context );
use Test2::Tools::Process ();
use Test2::Tools::Process::ReturnMultiLevel qw( with_return );
use base 'Exporter';

# ABSTRACT: Test that some code calls exec without terminating testing
# VERSION

=head1 SYNOPSIS

 use Test::More;
 use Test::Exec;
 
 is_deeply exec_arrayref { exec 'foo', 'bar', 'baz' }, [qw( foo bar baz )], 'found exec!';
 is exec_arrayref { }, undef, 'did not exec!';

=head1 DESCRIPTION

L<Test::Exec> provides the most simple possible tools for testing code that might call C<exec>, which
would otherwise end your test by calling another program.  This code should detect and capture C<exec>
calls, even if they are inside an C<eval>.

The concept was implementation was based on L<Test::Exit>, but applied to C<exec> instead of C<exit>.

=cut

our @EXPORT = qw( exec_arrayref never_exec_ok );

our $exec_handler = sub {
  CORE::exec(@_);
};
BEGIN {
  *CORE::GLOBAL::exec = sub { $exec_handler->(@_) };
}

=head1 FUNCTIONS

=head2 exec_arrayref

 exec_arrayref { ... }

runs the given code.  If the code calls C<exec>, then this function will return an arrayref with its
arguments.  If the code never calls C<exec>, it will return C<undef>.

=cut

my $last;

sub exec_arrayref(&)
{
  my($code) = @_;

  undef $last;

  return with_return {
    my($return) = @_;
    local $exec_handler = sub {
      $last = [caller(1)];
      $return->([@_]);
    };
    $code->();
    undef;
  };
}

=head2 never_exec_ok

 never_exec_ok { ... }

Runs the given code.  If the code calls C<exec>, then the test will fail (but exec will be intercepted
and not performed).

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

1;

=head1 CAVEATS

This module installs its own version of C<exec> in C<CORE::GLOBAL::exec>,
and may interact badly with any other code that is also trying to do
such things.

=head1 SEE ALSO

=over 4

=item L<Test::Exit>

Very similar to (and inspired) this module, but for C<exit> testing instead of C<exec>.

=item L<Test::Mock::Cmd>

Provides an interface to mocking C<system>, C<qx> and C<exec>.

=back

=cut
