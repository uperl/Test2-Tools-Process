use Test2::V0 -no_srand => 1;
use Test2::Tools::Process;

subtest 'export' => sub {
  imported_ok 'process';
  imported_ok 'proc_event';
};

subtest 'basic' => sub {

  process {
    note 'nothing';
  } [];

  process {
    note 'nothing';
  };

  process {
    note 'nothing';
  } [], 'custom test name 1';

  process {
    note 'nothing';
  } 'custom test name 2';

};

subtest 'exit' => sub {

  process {
    exit;
  } [
    proc_event exit => number(0),
  ];

  my $ret1;
  my $ret2;

  process {
    $ret1  = exit 2;
    $ret2  = exit;   ## no critic(ControlStructures::ProhibitUnreachableCode)
  } [
    proc_event( exit => 2, sub { return -42 }),
    proc_event( exit => 0),
  ];

  is $ret1, -42;
  is $ret2, U();

  is
    intercept { process { exit 2 } [ proc_event exit => 3 ] },
    array {
      event 'Fail';
      end;
    },
    'fail 1',
  ;

  is
    intercept { process { note 'nothing' } [ proc_event 'exit' ] },
    array {
      event 'Note';
      event 'Fail';
      etc;
    },
    'fail 1',
  ;

};

done_testing;
