package Test2::Tools::Process;

use strict;
use warnings;
use Test2::Tools::Compare ();
use Test2::API qw( context );
use Ref::Util qw( is_plain_arrayref is_ref );
use 5.008004;
use base qw( Exporter );

our @EXPORT = qw( process EXIT );

# ABSTRACT: Unit tests for code that calls exit, exec, system or qx()
# VERSION

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

our %handlers;
our %orig;

BEGIN {
  %orig = (
    exit     => \&CORE::exit,
    exec     => \&CORE::exec,
    system   => \&CORE::system,
    readpipe => \&CORE::readpipe,
  );

  %handlers = (
    exit     => sub (;$) { $orig{exit}->(@_) },
    exec     => sub { $orig{exec}->(@_) },
    system   => sub { $orig{system}->(@_) },
    readpipe => sub { $orig{readpipe}->(@_) },
  );

  no warnings 'redefine';
  *CORE::GLOBAL::exit     = sub (;$) { $handlers{exit}->(@_) };
  *CORE::GLOBAL::exec     = sub      { $handlers{exec}->(@_) };
  *CORE::GLOBAL::system   = sub      { $handlers{system}->(@_) };
  *CORE::GLOBAL::readpipe = sub      { $handlers{readpipe}->(@_) };
}

=head1 FUNCTIONS

=head2 process

=cut

sub process (&;@)
{
  my $sub = shift;
  my @expected  = ();
  my $test_name = 'process ok';
  my @events;
  my $i = 0;

  if(is_plain_arrayref $_[0])
  {
    @expected = @{ shift() };
  }

  $test_name = shift if defined $_[0];


  Test2::Tools::Process::ReturnMultiLevel::with_return(sub {
    my($return) = @_;

    local $handlers{exit}     = sub (;$) {
      my $expected = $expected[$i++];

      my $code = shift;
      $code = 0 unless defined $code;
      $code = int($code);
      push @events, ['exit', $code];

      if(defined $expected && $expected->is_exit && defined $expected->callback)
      {
        return $expected->callback->($code);
      }
      else
      {
        $return->();
      }
    };

    $sub->();
  });

  @_ = (
    \@events,
    [ map { $_->to_check } @expected ],
    $test_name
  );

  goto \&Test2::Tools::Compare::is;
}

=head1 CHECKS

=head2 EXIT

=cut

sub EXIT (;$$)
{
  my($check, $callback) = @_;

  my @caller = caller;

  if(defined $check && !is_ref $check)
  {
    unless(is_ref $check)
    {
      $check = Test2::Compare::Number->new(
        file => $caller[1],
        lines => [$caller[2]],
        input => $check,
      );
    }
  }
  else
  {
    $check = Test2::Compare::Custom->new(
      code     => sub { defined $_ ? 1 : 0 },
      name     => 'DEFINED',
      operator => 'DEFINED()',
      file => $caller[1],
      lines => [$caller[2]],
    );
  }

  Test2::Tools::Process::Exit->new(code_check => $check, callback => $callback);
}

package Test2::Tools::Process::Event;

use constant is_exit   => 0;
use constant is_exec   => 0;
use constant is_system => 0;
use Class::Tiny qw( callback );

package Test2::Tools::Process::Exit;

use constant is_exit => 1;
use base qw( Test2::Tools::Process::Event );
use Class::Tiny qw( code_check );

sub to_check
{
  my($self) = @_;
  ['exit', $self->{code_check} ];
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
