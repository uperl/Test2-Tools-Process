use Test2::V0 -no_srand => 1;
use Test2::Tools::Process;
use Capture::Tiny qw( capture_merged );

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
  capture_merged { system 'bogus' };
} [
  proc_event('system' => 'bogus', { error => D() }),
], 'bad command';

my $todo = todo 'signals test not working';

process {
  capture_merged { system q{bash -c 'kill $$'} };
} [
  proc_event('system' => { signal => 9 }),
], 'signal';

$todo->end;

done_testing;
