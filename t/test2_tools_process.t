use Test2::V0 -no_srand => 1;
use Test2::Tools::Process;

subtest 'export' => sub {
  imported_ok 'process';
  imported_ok 'EXIT';
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
    EXIT(number(0)),
  ];

  my $ret1;
  my $ret2;

  process {
    $ret1  = exit 2;
    $ret2  = exit;   ## no critic(ControlStructures::ProhibitUnreachableCode)
  } [
    EXIT(2, sub { return -42 }),
    EXIT(0),
  ];

  is $ret1, -42;
  is $ret2, U();

  is
    intercept { process { exit 2 } [ EXIT(3) ] },
    array {
      event 'Fail';
      end;
    },
    'fail 1',
  ;

  is
    intercept { process { exit 2 } [ EXIT(3) ] },
    array {
      event 'Fail';
      etc;
    },
    'fail 1',
  ;

};

done_testing;


