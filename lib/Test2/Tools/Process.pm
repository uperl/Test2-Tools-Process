package Test2::Tools::Process;

use strict;
use warnings;
use Test2::Tools::Compare ();
use Test2::API qw( context );
use Ref::Util qw( is_plain_arrayref is_ref is_plain_coderef );
use Carp qw( croak );
use Test2::Compare::Array     ();
use Test2::Compare::Wildcard  ();
use Test2::Compare::Number    ();
use Test2::Compare::String    ();
use Test2::Compare::Custom    ();
use Test2::Compare ();
use 5.008004;
use base qw( Exporter );

our @EXPORT = qw( process proc_event );

# ABSTRACT: Unit tests for code that calls exit, exec, system or qx()
# VERSION

=head1 SYNOPSIS

# EXAMPLE: t/test2_tools_process__synopsis.t

=head1 DESCRIPTION

TODO

=cut

our %handlers;

BEGIN {

  %handlers = (
    exit     => sub (;$) { CORE::exit(@_) },
    exec     => sub      { CORE::exec(@_) },
    system   => sub      { CORE::system(@_) },
    readpipe => sub (_)  { CORE::readpipe(@_) },
  );

  no warnings 'redefine';
  *CORE::GLOBAL::exit     = sub (;$) { $handlers{exit}->(@_) };
  *CORE::GLOBAL::exec     = sub      { $handlers{exec}->(@_) };
  *CORE::GLOBAL::system   = sub      { $handlers{system}->(@_) };
  *CORE::GLOBAL::readpipe = sub (_)  { $handlers{readpipe}->(@_) };
}

=head1 FUNCTIONS

=head2 process

 my $ok = process { ... } \@events, $test_name;
 my $ok = process { ... } \@events;
 my $ok = process { ... } $test_name;
 my $ok = process { ... };

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

    local $handlers{exit} = sub (;$) {
      my $expected = $expected[$i++];

      my $code = shift;
      $code = 0 unless defined $code;
      $code = int($code);
      push @events, { event_type => 'exit', exit_code => $code };

      if(defined $expected && $expected->is_exit && defined $expected->callback)
      {
        return $expected->callback->($return, $code);
      }
      else
      {
        $return->();
      }
    };

    local $handlers{exec} = sub {
      if(@_ == 1 || @_ == 0)
      {
        push @events, { event_type => 'exec', command => $_[0] };
      }
      else
      {
        push @events, { event_type => 'exec', command => [@_] };
      }

      my $expected = $expected[$i++];

      if(defined $expected && $expected->is_exec && defined $expected->callback)
      {
        return $expected->callback->($return, @_);
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

=head2 proc_event

 process { ... } [
   proc_event($type => $check, $callback);
   proc_event($type => $check);
   proc_event($type => $callback);
   proc_event($type);
 ];

The C<proc_event> function creates a process event, with an optional check and callback.  How the
C<$check> works depends on the C<$type>.  If no C<$check> is provided then it will only check that
the C<$type> matches.  Due to their nature, C<exit> and C<exec> events are emulated.  C<system>
events will actually make a system call, unless a C<$callback> is provided.

=over 4

=item exit

A process event for an C<exit> call.  The check is against the status value passed to C<exit>.  This
value will always be an integer.  If no status value was passed to C<exit>, C<0> will be used as
the status value.

If no callback is provided then an C<exit> will be emulated by terminating the process block without
executing any more code.  The rest of the test will then proceed.

 proc_event( exit => sub {
   my($return, $status) = @_;
   $return->();
 });

The callback takes a C<$return> callback and a C<$status> value.  C<exit> shouldn't ever fail so you
probably don't want to forget to call C<$return>.

=item exec

A process event for an C<exec> call.  The check is against the command passed to C<exec>.  If C<exec>
is called with a single argument this will be a string, otherwise it will be an array reference.
This way you can differentiate between the SCALAR and LIST modes of C<exec>.

If no callback is provided then a (successful) C<exec> will be emulated by terminating the process
block without executing any more code.  The rest of the test will then proceed.

 proc_event( exec => sub {
   my($return, @command) = @_;
   ...;
 });

The callback takes a C<$return> callback and the arguments passed to C<exec> as C<@command>.  You
can emulate a failed C<exit> by returning C<0> and setting C<$!>:

 proc_event( exec => sub {
   my($return, @command) = @_;
   $! = 2;
   return 0;
 });

To emulate a successful C<exec> call you want to just remember to call the C<$return> callback at
the end of your callback.

 proc_event( exec => sub {
   my($return, @command) = @_;
   $return->();
 });

=item system

TODO

=back

=cut

sub proc_event ($;$$)
{
  my $type = shift;
  croak("no such process event undef") unless defined $type;

  my $check;
  my $callback;

  $check = shift unless defined $_[0] && is_plain_coderef $_[0];

  if(defined $_[0])
  {
    if(is_plain_coderef $_[0])
    {
      $callback = shift;
    }
    else
    {
      croak("callback is not a code reference");
    }
  }

  my @caller = caller;

  if($type eq 'exit')
  {
    if(defined $check)
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

    return Test2::Tools::Process::Exit->new(code_check => $check, callback => $callback);
  }

  elsif($type eq 'exec')
  {
    if(defined $check)
    {
      if(is_plain_arrayref $check)
      {
        my $array = Test2::Compare::Array->new(
          called => \@caller,
        );
        foreach my $item (@$check)
        {
          my $wc = Test2::Compare::Wildcard->new(
            expect => $item,
            file   => $caller[1],
            lines  => [$caller[2]],
          );
          $array->add_item($wc);
        }
        $check = $array;
      }
      elsif(!is_ref $check)
      {
        $check = Test2::Compare::String->new(
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

    return Test2::Tools::Process::Exec->new( command_check => $check, callback => $callback);

  }

  croak("no such process event $type");
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
  { event_type => 'exit', exit_code => $self->{code_check} };
}

package Test2::Tools::Process::Exec;

use constant is_exec => 1;
use base qw( Test2::Tools::Process::Event );
use Class::Tiny qw( command_check );

sub to_check
{
  my($self) = @_;
  { event_type => 'exec', command => $self->{command_check} };
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

=head1 CAVEATS

The C<exit> emulation, doesn't call C<END> callbacks or other destructors, since
you aren't really terminating the process.

=cut
