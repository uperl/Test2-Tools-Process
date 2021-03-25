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
  proc_event exit => match qr/^[2-3]$/,
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
my $ok = process { ... };
```

# CHECKS

## proc\_event

```perl
process { ... } [
  proc_event($type => $check, $callback);
  proc_event($type => $check);
  proc_event($type => $callback);
  proc_event($type);
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
      my($return, $status) = @_;
      $return->();
    });
    ```

    The callback takes a `$return` callback and a `$status` value.  `exit` shouldn't ever fail so you
    probably don't want to forget to call `$return`.

- exec

    A process event for an `exec` call.  The check is against the command passed to `exec`.  If `exec`
    is called with a single argument this will be a string, otherwise it will be an array reference.
    This way you can differentiate between the SCALAR and LIST modes of `exec`.

    If no callback is provided then a (successful) `exec` will be emulated by terminating the process
    block without executing any more code.  The rest of the test will then proceed.

    ```perl
    proc_event( exec => sub {
      my($return, @command) = @_;
      ...;
    });
    ```

    The callback takes a `$return` callback and the arguments passed to `exec` as `@command`.  You
    can emulate a failed `exit` by returning `0` and setting `$!`:

    ```perl
    proc_event( exec => sub {
      my($return, @command) = @_;
      $! = 2;
      return 0;
    });
    ```

    To emulate a successful `exec` call you want to just remember to call the `$return` callback at
    the end of your callback.

    ```perl
    proc_event( exec => sub {
      my($return, @command) = @_;
      $return->();
    });
    ```

- system

    TODO

# CAVEATS

The `exit` emulation, doesn't call `END` callbacks or other destructors, since
you aren't really terminating the process.

# AUTHOR

Graham Ollis <plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2021 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
