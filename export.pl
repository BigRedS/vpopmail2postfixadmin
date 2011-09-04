#! /usr/bin/perl

# export.pl; part of vpopmail2postfixadmin.
#
# Exports a dump of the (interesting bits) of the current vpopmail
# configuration suitable for shoving into import.pl/.
#

use strict;

#use vpopmail;
use Mail::vpopmail;
use Data::Dumper;
$Data::Dumper::Purity = 1;

my %data;

my $vpopmail = Mail::vpopmail->new(debug=>'0');

my %data;
my @domains = @{$vpopmail->alldomains(field => 'name')};
foreach my $domain (@domains){
	my @mailboxes = @{$vpopmail->domaininfo(domain => $domain, field=>'mailboxes')};
	foreach my $user (@mailboxes){
		my $email = $user.'@'.$domain;
		my @forwardto;
		#print $email."  ";
		$data{$domain}{$email}{'dir'}     = $vpopmail->userinfo(email=>$email, field=>'dir');
		$data{$domain}{$email}{'plain'}   = $vpopmail->userinfo(email=>$email, field=>'plain');
		$data{$domain}{$email}{'comment'} = $vpopmail->userinfo(email=>$email, field=>'comment');
		$data{$domain}{$email}{'quota'}   = $vpopmail->userinfo(email=>$email, field=>'quota');
		my @dotQmailFile = getDotQmailFile($data{$domain}{$email}{'dir'}, $user);
		foreach(@dotQmailFile){
			if (/^\s*\&(.+)/){push(@forwardto, $1);}
		}
		$data{$domain}{$email}{'forwardto'} = \@forwardto;
		$data{$domain}{$email}{'dotqmail'} = \@dotQmailFile;
	}
}
print Dumper(%data);


sub getDotQmailFile{
	my $dir = shift;
	my $user = shift;
	my $file = $dir."/.qmail-$user";
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
