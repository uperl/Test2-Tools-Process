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
  my $ret3;

  process {
    $ret1  = exit 2;
    $ret2  = exit 3;
    $ret3  = exit;
  } [
    proc_event( exit => 2, sub { return -42 }),
    proc_event( exit => sub { return -43 }),
    proc_event( exit => 0),
  ];

  is $ret1, -42;
  is $ret2, -43;
  is $ret3, U();

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

subtest 'exec' => sub {

  process { exec; } [ proc_event( exec => U() ) ];

  process { exec 'hi'; } [
    proc_event(exec => 'hi'),
  ];

  process { exec 'bye'; } [
    proc_event(exec => match qr/^b/),
  ];

  process { exec 'hi', 'bye' } [
    proc_event(exec => array {
      item 'hi';
      item match qr/^b/;
      end;
    }),
  ];

#  process { exec 'hi', 'bye' } [
#    proc_event(exec => ['hi','bye']),
#  ];

  is
    intercept { process { note 'nothing' } [ proc_event 'exec' ] },
    array {
      event 'Note';
      event 'Fail';
    },
    'fail 1',
  ;

  is
    intercept { process { exec; } [ proc_event 'exec' => D() ] },
    array {
      event 'Fail';
    },
    'fail 2',
  ;

  is
    intercept { process { exec 'hi'; } [ proc_event 'exec' => 'bye' ] },
    array {
      event 'Fail';
    },
    'fail 3',
  ;

  is
    intercept { process { exec 'bye'; } [ proc_event 'exec' => match qr/^h/ ] },
    array {
      event 'Fail';
    },
    'fail 4',
  ;

  is
    intercept {
      process { exec 'hi', 'bye' } [
        proc_event(exec => array {
          item 'hi';
          item match qr/^x/;
          end;
        }),
      ];
    },
    array {
      event 'Fail';
    },
    'fail 5',
  ;

};

done_testing;
