package Test2::Tools::Process;

use strict;
use warnings;
use Test2::Tools::Compare ();
use Test2::API qw( context );
use Ref::Util qw( is_plain_arrayref is_ref is_plain_coderef is_plain_hashref );
use Carp qw( croak carp );
use Test2::Compare::Array     ();
use Test2::Compare::Wildcard  ();
use Test2::Compare::Number    ();
use Test2::Compare::String    ();
use Test2::Compare::Custom    ();
use Test2::Compare ();
use 5.008004;
use base qw( Exporter );

our @EXPORT = qw( process proc_event named_signal );
our @CARP_NOT = qw( Test2::Tools::Process::SystemProc );

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

    local %handlers = %handlers;

    $handlers{exit} = sub (;$) {
      my $expected = $expected[$i++];

      my $status = shift;
      $status = 0 unless defined $status;
      $status = int($status);
      push @events, { event_type => 'exit', exit_status => $status };

      if(defined $expected && $expected->is_exit && defined $expected->callback)
      {
        my $proc = Test2::Tools::Process::Proc->new($return);
        my $ret = $expected->callback->($proc, $status);
        if(exists $proc->{errno})
        {
          $! = $proc->{errno};
          return 0;
        }
        return $ret;
      }
      else
      {
        $return->();
      }
    };

    $handlers{exec} = sub {
      my $expected = $expected[$i++];

      if(@_ == 1 || @_ == 0)
      {
        push @events, { event_type => 'exec', command => $_[0] };
      }
      else
      {
        push @events, { event_type => 'exec', command => [@_] };
      }

      if(defined $expected && $expected->is_exec && defined $expected->callback)
      {
        my $proc = Test2::Tools::Process::Proc->new($return);
        my $ret = $expected->callback->($proc, @_);
        if(exists $proc->{errno})
        {
          $! = $proc->{errno};
          return 0;
        }
        return $ret;
      }
      else
      {
        $return->();
      }
    };

    $handlers{system} = sub {
      my $expected = $expected[$i++];

      my $event;
      my $args = \@_;
      if(@_ == 1 || @_ == 0)
      {
        push @events, $event = { event_type => 'system', command => $_[0] };
      }
      else
      {
        push @events, $event = { event_type => 'system', command => [@_] };
      }

      if(defined $expected && $expected->is_system && defined $expected->callback)
      {
        Test2::Tools::Process::ReturnMultiLevel::with_return(sub {
          my($return) = @_;
          my $proc = Test2::Tools::Process::SystemProc->new($return, $event);
          $expected->callback->($proc, @$args);
          $event->{status} = 0;
          $? = 0;
        });
        return -1 if exists $event->{errno};
        return $?;
      }
      else
      {
        local $SIG{__WARN__} = sub {
          my($message) = @_;
          $message =~ s/ at .*? line [0-9]+\.$//;
          chomp $message;
          carp($message);
        };
        my $ret = CORE::system(@_);
        if($? == -1)
        {
          $event->{errno} = $!;
        }
        elsif($? & 127)
        {
          $event->{signal} = $? & 127;
        }
        else
        {
          $event->{status} = $? >> 8;
        }
        return $ret;
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

=head2 named_signal

 my $signame = named_signal $name;

Given a string signal name like C<KILL>, this will return the integer
signal number.  It will throw an exception if the C<$name> is invalid.

=cut

{
  my $sig;
  sub named_signal ($)
  {
    my($name) = @_;

    # build hash on demand.
    $sig ||= do {
      require Config;
      my %sig;
      my @num = split /\s+/, $Config::Config{sig_num};
      foreach my $name (split /\s+/, $Config::Config{sig_name})
      {
        $sig{$name} = shift @num;
      }
      \%sig;
    };

    croak "no such signal: $name" unless exists $sig->{$name};

    $sig->{$name};
  }
}

=head1 CHECKS

=head2 proc_event

 process { ... } [
   proc_event($type => $check, $callback),
   proc_event($type => $check),
   proc_event($type => $callback),
   proc_event($type),
 
   # additional result checks for `system` events
   proc_event('system' => $check, \%result_check, $callback),
   proc_event('system' => \%result_check, $callback),
   proc_event('system' => $check, \%result_check),
   proc_event('system' => \%result_check),
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
   my($proc, $status) = @_;
   $proc->terminate;
 });

The callback takes a C<$proc> object and a C<$status> value.  Normally C<exit> should never
return, so what you want to do is call the C<terminate> method on the C<$proc> object.

=item exec

A process event for an C<exec> call.  The check is against the command passed to C<exec>.  If C<exec>
is called with a single argument this will be a string, otherwise it will be an array reference.
This way you can differentiate between the SCALAR and LIST modes of C<exec>.

If no callback is provided then a (successful) C<exec> will be emulated by terminating the process
block without executing any more code.  The rest of the test will then proceed.

 proc_event( exec => sub {
   my($proc, @command) = @_;
   ...;
 });

The callback takes a C<$proc> object and the arguments passed to C<exec> as C<@command>.  You
can emulate a failed C<exec> by using the C<errno> method on the C<$proc> object:

 proc_event( exec => sub {
   my($proc, @command) = @_;
   $proc->errno(2); # this is the errno value
 });

To emulate a successful C<exec> call you want to just remember to call the C<terminate> method on
the C<$proc> object.

 proc_event( exec => sub {
   my($proc, @command) = @_;
   $proc->terminate;
 });

=item system

A process event for C<system>, C<piperead> and C<qx//>.  The first check (as with C<exec>) is against
the command string passed to C<system>.  The second is a hash reference with result checks.

=over 4

=item status

 proc_event( system => { status => $check } );

The normal termination status.  This is usually the value passed to C<exit> in the program called.  Typically
a program that succeeded will return zero (C<0>) and a failed on will return non-zero.

=item errno

 proc_event( system => { errno => $check } );

The C<errno> or C<$!> value if the system call failed.  Most commonly this is for bad command names, but it
could be something else like running out of memory or other system resources.

=item signal

 proc_event( system => { signal => $check } );

Set if the process was killed by a signal.

=back

Only one check should be included because only one of these is usually valid.  If you do not provide this check,
then it will check that the status code is zero only.

# TODO: callback

=back

=cut

sub proc_event ($;$$$)
{
  my $type = shift;
  croak("no such process event undef") unless defined $type;

  my $check;
  my $check2;
  my $callback;

  $check  = shift if defined $_[0] && !is_plain_coderef $_[0] && !is_plain_hashref $_[0];
  $check2 = shift if defined $_[0] && is_plain_hashref $_[0];

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

    return Test2::Tools::Process::Exit->new(status_check => $check, callback => $callback);
  }

  elsif($type =~ /^(exec|system)$/)
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

    if($type eq 'system')
    {
      $check2 ||= { status => 0 };
    }

    my $class = $type eq 'exec'
      ? 'Test2::Tools::Process::Exec'
      : 'Test2::Tools::Process::System';
    return $class->new( command_check => $check, result_check => $check2, callback => $callback);
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
use Class::Tiny qw( status_check );

sub to_check
{
  my($self) = @_;
  { event_type => 'exit', exit_status => $self->status_check };
}

package Test2::Tools::Process::Exec;

use constant is_exec => 1;
use base qw( Test2::Tools::Process::Event );
use Class::Tiny qw( command_check );

sub to_check
{
  my($self) = @_;
  { event_type => 'exec', command => $self->command_check };
}

package Test2::Tools::Process::System;

use constant is_system => 1;
use base qw( Test2::Tools::Process::Event );
use Class::Tiny qw( command_check result_check );

sub to_check
{
  my($self) = @_;
  { event_type => 'system', command => $self->command_check, %{ $self->result_check } };
}

package Test2::Tools::Process::Proc;

sub new
{
  my($class, $return) = @_;
  bless {
    return => $return,
  }, $class;
}

sub terminate { shift->{return}->() }

sub errno
{
  my($self, $errno) = @_;
  $self->{errno} = $errno;
}

package Test2::Tools::Process::SystemProc;

sub new
{
  my($class, $return, $result) = @_;
  bless {
    return => $return,
    result => $result,
  }, $class;
}

sub exit
{
  my($self, $status) = @_;
  $status = 0 unless defined $status;
  $status = int $status;
  $self->{result}->{status} = $status;
  $? = $status << 8;
  $self->{return}->();
}

sub signal
{
  my($self, $signal) = @_;
  $signal = 0 unless defined $signal;
  if($signal =~ /^[A-Z]/i)
  {
    $signal = Test2::Tools::Process::named_signal($signal);
  }
  else
  {
    $signal = int $signal;
  }
  $self->{result}->{signal} = $signal;
  $? = $signal;
  $self->{return}->();
}

sub errno
{
  my($self, $errno) = @_;
  $errno = 0 unless defined $errno;
  $errno = int $errno;
  $self->{result}->{errno} = $! = $errno;
  $self->{return}->();
}

package Test2::Tools::Process::ReturnMultiLevel;

# this is forked from Return::MultiLevel (XS implementation only)
# we can remove this when it gets a maintainer again.

use Scope::Upper;
use Carp ();
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

This module installs handlers for C<exec>, C<exit>, C<system> and C<readpipe>, in
the C<CORE::GLOBAL> namespace, so if your code is also installing handlers there
then things might not work.

=head1 SEE ALSO

=over 4

=item L<Test::Exit>

Simple C<exit> emulation for tests.  The most recent version does not rely on exceptions.

=item L<Test::Exec>

Like L<Test::Exit>, but for C<exec>

=item L<Test::Mock::Cmd>

Provides an interface to mocking C<system>, C<qx> and C<exec>.

=back

=cut
