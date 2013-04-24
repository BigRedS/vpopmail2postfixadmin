#! /usr/bin/perl

# export.pl; part of vpopmail2postfixadmin.
#
# Exports a dump of the (interesting bits) of the current vpopmail
# configuration suitable for shoving into import.pl/.
#

use strict;

use Mail::vpopmail;
use YAML;

my $vpopmail = Mail::vpopmail->new(debug=>'0');

my $file = $ARGV[0] || usage();

my %data;
my %data = getDomains();
foreach my $domain (keys(%data)){
	my @mailboxes = @{$vpopmail->domaininfo(domain => $domain, field=>'mailboxes')};
	$data{$domain}{'dir'} = $vpopmail->domaininfo(domain => $domain, field=>'dir')."";
	$data{$domain}{'actions'} = parseDotQmailFile(getDotQmailFilePath($data{$domain}{'dir'}, "default"));
	foreach my $user (@mailboxes){
		my $email = $user.'@'.$domain;
		$data{$domain}{'mailboxes'}{$email}{'dir'}     = $vpopmail->userinfo(email=>$email, field=>'dir')."/$user";
		$data{$domain}{'mailboxes'}{$email}{'plain'}   = $vpopmail->userinfo(email=>$email, field=>'plain');
		$data{$domain}{'mailboxes'}{$email}{'comment'} = $vpopmail->userinfo(email=>$email, field=>'comment');
		$data{$domain}{'mailboxes'}{$email}{'quota'}   = $vpopmail->userinfo(email=>$email, field=>'quota');
		my $dotQmailFilePath = getDotQmailFilePath($data{$domain}{'dir'}, $user);
		$data{$domain}{'mailboxes'}{$email}{'actions'} = parseDotQmailFile($dotQmailFilePath);
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
		$domains{$domain}{'dir'}=$vpopmail->domaininfo(domain=>$domain, field=>'map');
	}
	return %domains;
}

sub getDotQmailFilePath{
	my $directory = shift;
	my $user = shift;
	$user =~ s/\./:/;
	my $file = $directory."/.qmail-$user";
	return $file;
}

# Passed a (domain) directory and a user, retrieves that user's .qmail file,
# and returns its contents as a one-line-per-element array
sub getDotQmailFile{
	my $file = shift;
	if(-f $file){
		my ($f,@file);
		eval{ 
			open($f, "<", $file) or die "Error opening $file for reading";
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

sub parseDotQmailFile{
		my $dotQmailFilePath = shift;
		my @dotQmailFile = getDotQmailFile($dotQmailFilePath);
		my (@forwardto,@pipeto,@deliverto,@unknown);
		my $line = 0;
		my $return;
		foreach(@dotQmailFile){
			$line++;
			if (/^\s*\|(.+)$/){
				push(@pipeto, $1);
				$_="";
			}elsif (/^([\.\/].+)$/){
				push(@deliverto, $1);
				$_="";
			}elsif (/^\s*\&?([\d[a-z].+\@.+)/){
				push(@forwardto, $1);
				$_="";
			}else{
				_warn("Unhandled dot-qmail file line: '".$_."' in '$dotQmailFilePath' on line $line");
				push(@unknown, $_);
			}
		}
		$return->{'pipeto'} = \@pipeto;
		$return->{'deliverto'} = \@deliverto;
		$return->{'forwardto'} = \@forwardto;
		$return->{'unknown'}   = \@unknown;
		return $return;
}
sub _warn{
	my $message = shift;
	chomp $message;
	print STDERR $message."\n";
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
