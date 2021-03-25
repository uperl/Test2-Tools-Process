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
  proc_event(exec => match qr/^foo\b/, sub {
    my($return, @command) = @_;
    # emulate a failed exec
    $! = 2;
    return 0;
  }),
  # the second exec will be emulated
  proc_event('exec'),
];

done_testing;
