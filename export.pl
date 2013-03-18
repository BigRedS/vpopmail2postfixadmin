#! /usr/bin/perl

# export.pl; part of vpopmail2postfixadmin.
#
# Exports a dump of the (interesting bits) of the current vpopmail
# configuration suitable for shoving into import.pl/.
#

use strict;

use Mail::vpopmail;
use Data::Dumper;
use YAML;
$Data::Dumper::Purity = 1;
$Data::Dumper::Useqq = 1;

my $vpopmail = Mail::vpopmail->new(debug=>'0');

my $file = $ARGV[0] || usage();

my %data;
my %data = getDomains();
foreach my $domain (keys(%data)){
	my @mailboxes = @{$vpopmail->domaininfo(domain => $domain, field=>'mailboxes')};
	foreach my $user (@mailboxes){
		my $email = $user.'@'.$domain;
		my (@forwardto,@pipeto,@deliverto,@unknown);
		#print $email."  ";
		$data{$domain}{'mailboxes'}{$email}{'dir'}     = $vpopmail->userinfo(email=>$email, field=>'dir');
		$data{$domain}{'mailboxes'}{$email}{'plain'}   = $vpopmail->userinfo(email=>$email, field=>'plain');
		$data{$domain}{'mailboxes'}{$email}{'comment'} = $vpopmail->userinfo(email=>$email, field=>'comment');
		$data{$domain}{'mailboxes'}{$email}{'quota'}   = $vpopmail->userinfo(email=>$email, field=>'quota');
		my @dotQmailFile = getDotQmailFile($data{$domain}{'mailboxes'}{$email}{'dir'}, $user);
		foreach(@dotQmailFile){
			if (/^\s*\|(.+)$/){
				push(@pipeto, $1);
				$_="";
			}elsif (/^([\.\/].+)$/){
				push(@deliverto, $1);
				$_="";
			}elsif (/^\s*\&?(.+\@.+)/){
				push(@forwardto, $1);
				$_="";
			}else{
				push(@unknown, $_);
			}
		}
		@dotQmailFile = grep(!/^\s*$/, @dotQmailFile);
		$data{$domain}{'mailboxes'}{$email}{'actions'}{'forwardto'} = \@forwardto;
		$data{$domain}{'mailboxes'}{$email}{'actions'}{'dotqmail'} = \@dotQmailFile;
		$data{$domain}{'mailboxes'}{$email}{'actions'}{'pipeto'} = \@pipeto;
		$data{$domain}{'mailboxes'}{$email}{'actions'}{'deliverto'} = \@deliverto;
		$data{$domain}{'mailboxes'}{$email}{'actions'}{'unhandled'} = \@unknown;
	}
}

YAML::DumpFile($file, %data);

# Passed nothing, returns a hash whose keys are domain names, and each
# domain has a 'name' element containing its name (equiv. to the key)
# and, if there are any, an 'aliases' element, containing an array of
# domains which are aliases to this one.
sub getDomains{
	my %domains;
	foreach(qx/vdominfo -n/){
		/^(\S+)/;
		my $domain = $1;
		if (/\(alias of (.+)\)/){
			my $alias = $1;
			push(@{$domains{$domain}{'aliases'}}, $1);
		}
		$domains{$domain}{'name'}="$domain";
	}
	return %domains;
}

# Passed a (domain) directory and a user, retrieves that user's .qmail file,
# and returns its contents as a one-line-per-element array
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

sub usage(){

print <<EOF;
	export.pl

	part of vpopmail2postfixadmin

usage:

	export.pl <filename>

dumps the configuration of a vpopmail system to 
<filename>, in a format understood by import.pl, 
which will import it to a postfixadmin system.

EOF

exit 1;

}
