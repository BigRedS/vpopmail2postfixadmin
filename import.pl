#! /usr/bin/perl

use Data::Dumper;

my $file = $ARGV[0];

$/ = undef;

open($f, "<", $file);
my $string = <$f>;
close($f);

my %hash = %{eval($string)};

foreach(keys(%hash)){
	print $_."\n";
}
