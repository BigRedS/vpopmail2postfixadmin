#! /usr/bin/perl

# export.pl; part of vpopmail2postfixadmin.
#
# Exports a dump of the (interesting bits) of the current vpopmail
# configuration suitable for shoving into import.pl/.
#
##Todo: Handle aliases. Oops
##Todo: Be able to run on a remote server by doing things via SSH.

use strict;

use vpopmail;
use Data::Dumper;
$Data::Dumper::Purity = 1;

my %data;

foreach my $domain (vlistdomains()) {
#my $domain = 'coolcars4hire.co.uk';
	foreach my $user (vlistusers($domain)){
		my $username = $user->{pw_name}."@".$domain;
		my $clearTextPassword = &getClearTextPassword($username);
		$data{$username}{username}=$username;
		$data{$username}{password}=$clearTextPassword;
		$data{$username}{directory}=$user->{pw_dir};
		my @dotQmail = getDotQmailFile($user->{pw_dir});
		my @forwards; # = grep( /^\&(\S+)/, @dotQmail);
		foreach(@dotQmail){
			if (/^\|\s+\S+autorespond\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/){
				my %autorespond = (
					time => $1,
					count => $2,
					message => getVacationMessage($3),
					directory => $4,
				);
				$data{$username}{autorespond}=\%autorespond;
			}elsif(/^\&(\S+)/){
				push(@forwards,$1);
			}
		}


		$data{$username}{forwards} = \@forwards;
		$data{$username}{dotqmail} = \@dotQmail;
	}
}

print Dumper(\%data);


sub getVacationMessage{
	my $file = shift;
	if (-f $file){
		my $f;
		eval{
			open($f, "<", $file) or die "Error opening vacation message at $file for reading";
		};
		print $@;
		return if ($@);
		my @file = (<$f>);
		my $message = join(/\n/, @file);
		return $message;
	}
	return;
}

sub getDotQmailFile{
	my $dir = shift;
	my $file = $dir."/.qmail";
	if(-f $file){
		my ($f,@file);
		eval{ 
			open($f, "<", $file) or die "Error opening $file for writing";
		};
		return if($@);
		foreach(<$f>){
			chomp $_;
			push(@file, $_);
		}
		close($f);
		return @file;
	}
	return;
}

sub getClearTextPassword{
	my $user = shift;
	my $password;
	foreach(`vuserinfo $user`){
		if (/clear passwd: (\S+)/){
			return $1;
			last;
		}
	}
	return;
}
