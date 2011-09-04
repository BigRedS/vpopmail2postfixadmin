#! /usr/bin/perl

# import.pl; part of vpopmail2postfixadmin
#
# Imports the dump produced by export.pl, and uses it to configure
# postfixadmin.

##Todo: strict-compatible version of `my %config = %{eval $dump};`


#use strict;

use lib '/home/avi/bin/vpostmail';

use Data::Dumper;
use Vpostmail;

# Import the dump:
my $file = $ARGV[0];
$/ = undef;
open(my $f, "<", $file);
#my $dump = <$f>;
#close($f);
my %config = %{eval <$f>};

# Create a vpostmail object:
my $v = Vpostmail->new(
	mysqlconf => '/home/avi/bin/.vmail.mysql.conf',
);

foreach my $domain (keys(%config)){
	foreach my $email (keys(%{$config{$domain}})){
		print $email."\n";
		foreach (keys(%{$config{$domain}{$email}})){
			print "\t$_ => $config{$domain}{$email}{$_}\n\n";
		}
	}
}


