#!/usr/bin/perl

use warnings;
use strict;
use IPC::Open3;
use IO::Select;
use Symbol;
use Time::HiRes qw/time/;

$SIG{__DIE__} = \&Carp::croak;
$SIG{__WARN__} = \&Carp::cluck;

$|++;

my $chld_in;
my $chld_out;
my $chld_err;
$chld_err = gensym(); # need to create a symbol for stderr

my $pid;

$SIG{TERM} = sub { my $sig = shift; if ($pid) { logger($$,'WARN',sprintf("Caught signal %s, passing it on to child pid %d",$sig,$pid)); kill $sig, $pid; }};
$SIG{INT} = $SIG{TERM};
$SIG{CHLD} = sub { my $sig = shift; if ($pid) { logger($$,'WARN',sprintf("Caught signal %s from child pid %d",$sig,$pid)); } };

$pid = open3($chld_in, $chld_out, $chld_err, @ARGV );

my $fds = { $chld_out => 'STDOUT', $chld_err => 'STDERR' };

my $fd_select = IO::Select->new();
$fd_select->add(\*STDIN, $chld_out, $chld_err);

my $okToRun = 1;
while ($okToRun && (my @ready = $fd_select->can_read)) {
  foreach my $fd (@ready) {
    unless (my $line = <$fd>) {
      $fd_select->remove($fd);
      close($chld_in) unless $fds->{$fd};
      delete $fds->{$fd};
      if (!scalar keys %$fds) {
        $okToRun = 0;
        last;
      }
      
    } elsif ($fds->{$fd}) {
      chomp($line);
      logger($pid, $fds->{$fd}, $line);
    } else {
      print $chld_in $line;
    }
  }
}

logger($$,'INFO',sprintf "Waiting for pid %d", $pid);
waitpid($pid,0);
logger($$,'INFO',sprintf "Exiting");
exit $? >> 8;

sub logger {
  my $pid = shift;
  my $level = shift;
  my @lines = @_;
  foreach my $line (map { split /\n/, $_ } @lines) {
    chomp($line);
    my $epoch = time;
    my @t=localtime(int $epoch);
    my $frac = 1000000 * ($epoch - int $epoch);
    printf "%04d-%02d-%02d %02d:%02d:%02d.%06d [%s] %s: %s\n",$t[5]+1900,$t[4]+1,@t[3,2,1,0],$frac, $pid, $level, $line;
  }
}
