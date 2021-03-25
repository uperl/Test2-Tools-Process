use Test2::V0 -no_srand => 1;
use Test2::Tools::Process;

skip_all 'CI only' unless ($ENV{CIPSOMETHING}||'') eq 'true';

process {
  system 'true';
} [
  proc_event('system' => 'true'),
], 'normal';

process {
  system 'false';
} [
  proc_event('system' => 'false', { status => 1 }),
], 'return non-zero';

process {
  system 'bogus';
} [
  proc_event('system' => 'bogus', { error => D() }),
], 'bad command';

my $todo = todo 'signals test not working';

process {
  system q{perl -e 'kill "TERM", $$'}
} [
  proc_event('system' => { signal => 9 }),
], 'signal';

$todo->end;

done_testing;
