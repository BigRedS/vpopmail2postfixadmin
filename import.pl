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
my $dump = <$f>;
close($f);
my %config = %{eval $dump};

# Create a vpostmail object:
my $v = Vpostmail->new(
	mysqlconf => '/home/avi/bin/.vmail.mysql.conf',
);

foreach(keys(%config)){
	/(.+)@/;
	my $user = $1;
	my $domain = $_;
	my $password = $config{$_}{'password'};
	$v->setDomain($domain);
	unless($v->domainExists){
		print "Creating $domain\n";
		$v->createDomain;
	}
	print "Creating $user\n";
	$v->setUser($_);
	$v->createUser;
	$v->changePassword($password);

}


