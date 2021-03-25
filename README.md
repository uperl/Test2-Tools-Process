# Test2::Tools::Process ![linux](https://github.com/uperl/Test2-Tools-Process/workflows/linux/badge.svg) ![windows](https://github.com/uperl/Test2-Tools-Process/workflows/windows/badge.svg) ![macos](https://github.com/uperl/Test2-Tools-Process/workflows/macos/badge.svg) ![cygwin](https://github.com/uperl/Test2-Tools-Process/workflows/cygwin/badge.svg) ![msys2-mingw](https://github.com/uperl/Test2-Tools-Process/workflows/msys2-mingw/badge.svg)

Unit tests for code that calls exit, exec, system or qx()

# SYNOPSIS

```perl
use Test2::V0 -no_srand => 1;
use Test2::Tools::Process;

process {
  exit 2;
  note 'not executed';
} [
  # can use any Test2 checks on the exit status
  proc_event(exit => match qr/^[2-3]$/),
];

process {
  exit 4;
} [
  # or you can just check that the exit status matches numerically
  proc_event(exit => 4),
];

process {
  exit 5;
} [
  # or just check that we called exit.
  proc_event('exit'),
];

process {
  exec 'foo bar';
  exec 'baz';
  note 'not executed';
} [
  # emulate first exec as failed
  proc_event(exec => match qr/^foo\b/, sub {
    my($return, @command) = @_;
    $! = 2;
    return 0;
  }),
  # the second exec will be emulated as successful
  proc_event('exec'),
];

done_testing;
```

# DESCRIPTION

TODO

# FUNCTIONS

## process

```perl
my $ok = process { ... } \@events, $test_name;
my $ok = process { ... } \@events;
my $ok = process { ... } $test_name;
my $ok = process { ... };
```

# CHECKS

## proc\_event

```perl
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
```

The `proc_event` function creates a process event, with an optional check and callback.  How the
`$check` works depends on the `$type`.  If no `$check` is provided then it will only check that
the `$type` matches.  Due to their nature, `exit` and `exec` events are emulated.  `system`
events will actually make a system call, unless a `$callback` is provided.

- exit

    A process event for an `exit` call.  The check is against the status value passed to `exit`.  This
    value will always be an integer.  If no status value was passed to `exit`, `0` will be used as
    the status value.

    If no callback is provided then an `exit` will be emulated by terminating the process block without
    executing any more code.  The rest of the test will then proceed.

    ```perl
    proc_event( exit => sub {
      my($proc, $status) = @_;
      $proc->terminate;
    });
    ```

    The callback takes a `$proc` object and a `$status` value.  Normally `exit` should never
    return, so what you want to do is call the `terminate` method on the `$proc` object.

- exec

    A process event for an `exec` call.  The check is against the command passed to `exec`.  If `exec`
    is called with a single argument this will be a string, otherwise it will be an array reference.
    This way you can differentiate between the SCALAR and LIST modes of `exec`.

    If no callback is provided then a (successful) `exec` will be emulated by terminating the process
    block without executing any more code.  The rest of the test will then proceed.

    ```perl
    proc_event( exec => sub {
      my($proc, @command) = @_;
      ...;
    });
    ```

    The callback takes a `$proc` object and the arguments passed to `exec` as `@command`.  You
    can emulate a failed `exec` by using the `fail` method on the `$proc` object:

    ```perl
    proc_event( exec => sub {
      my($proc, @command) = @_;
      $proc->fail(2); # this is the errno value
    });
    ```

    To emulate a successful `exec` call you want to just remember to call the `terminate` method on
    the `$proc` object.

    ```perl
    proc_event( exec => sub {
      my($proc, @command) = @_;
      $proc->terminate;
    });
    ```

- system

    A process event for `system`, `piperead` and `qx//`.  The first check (as with `exec`) is against
    the command string passed to `system`.  The second is a hash reference with result checks.

    - status

        ```perl
        proc_event( system => { status => $check } );
        ```

        The normal termination status.  This is usually the value passed to `exit` in the program called.  Typically
        a program that succeeded will return zero (`0`) and a failed on will return non-zero.

    - error

        ```perl
        proc_event( system => { error => $check } );
        ```

        The `errno` or `$!` value if the system call failed.  Most commonly this is for bad command names, but it
        could be something else like running out of memory or other system resources.

    - signal

        ```perl
        proc_event( system => { signal => $check } );
        ```

        Set if the process was killed by a signal.

    Only one check should be included because only one of these is usually valid.  If you do not provide this check,
    then it will check that the status code is zero only.

    \# TODO: callback

# CAVEATS

The `exit` emulation, doesn't call `END` callbacks or other destructors, since
you aren't really terminating the process.

This module installs handlers for `exec`, `exit`, `system` and `readpipe`, in
the `CORE::GLOBAL` namespace, so if your code is also installing handlers there
then things might not work.

# SEE ALSO

- [Test::Exit](https://metacpan.org/pod/Test::Exit)

    Simple `exit` emulation for tests.  The most recent version does not rely on exceptions.

- [Test::Exec](https://metacpan.org/pod/Test::Exec)

    Like [Test::Exit](https://metacpan.org/pod/Test::Exit), but for `exec`

- [Test::Mock::Cmd](https://metacpan.org/pod/Test::Mock::Cmd)

    Provides an interface to mocking `system`, `qx` and `exec`.

# AUTHOR

Graham Ollis <plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2015-2021 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
