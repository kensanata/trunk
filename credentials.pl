#!/usr/bin/env perl
use Modern::Perl;
open(my $fh, '<', 'credentials') or die "Cannot open credentials: $!";
my %h;
while (<$fh>) {
  my ($instance) = split;
  $h{$instance}++;
}
for my $instance (keys %h) {
  print "$instance $h{$instance}\n" if $h{$instance} > 1;
}
