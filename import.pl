#! /usr/bin/perl

# import.pl; part of vpopmail2postfixadmin
#
# Imports the dump produced by export.pl, and uses it to configure
# postfixadmin.

use strict;

use 5.010;

use lib "/home/avi/Mail-Postfixadmin/lib";
use Mail::Postfixadmin;
use Data::Dumper;
use Getopt::Std;
use YAML qw/LoadFile/;
my %o;
my %options;

# Options:
# d  dry run
# f  yaml file
# g  expression with which to generate passwords
# h  help
# p  file to write generated passwords to
# v  verbosity level
#Verbosity:
#1: can't-configures only (stdout)
#2: 1 + domains
#3: 2 + email addresses
#4: 3 + params
#5: 4 + 
#9: 5 + clear passwords(!?)
getopts('dv:f:g:p:', \%options);
#$o{verbose} = $options{v} || 2;
my $verbosity = $options{v} || 2;
my $file = $options{f};
my $f_passwords = $options{p} || "./passwords";
my $pwgen = $options{g} || 'pwgen 10 1';
$o{dryrun} = 3 if exists($options{d});
if ( exists($options{h}) || $file =~ /^$/){
	usage();
}

my $p = Mail::Postfixadmin->new();


# Import the dump:
my %config = LoadFile($file);

print "Verbosity: $verbosity\n";

# A hashref we'll populate with observations and
# then print out at the end:
my $messages;
# And one to store our generated passwords in:
my $generatedPasswords;

foreach my $domainName (keys(%config)){
	next if $domainName eq '';
	print "Configuring $domainName\n" if $verbosity > 1;
	my $domain = $config{$domainName};
	$domain->{'name'} = $domainName;
	$domain->{'actions'} = processActions($domain->{'actions'});
	#TODO: have processActions prune these arrayrefs of empty elements:
	if(scalar($domain->{'actions'}{'pipeto'})>0){
		foreach(@{$domain->{'actions'}{'pipeto'}}){
			push(@{$messages->{'domainpipe'}}, "$domainName: $_") if $_ =~ /.+/;
		}
	}
	if(scalar($domain->{'actions'}{'unknown'})>0){
		foreach(@{$domain->{'actions'}{'unknown'}}){
			push(@{$messages->{'domainunknown'}}, "domainName: $_") if $_ =~ /.+/;
		}
	}
	configureDomain($domain);
	foreach my $emailAddress (keys(%{$domain->{'mailboxes'}})){
		print "  Configuring $emailAddress\n" if $verbosity > 2;
		my $actions = $config{$domain}{'mailboxes'}{$emailAddress}{'actions'};
		if (scalar($actions->{'pipeto'}) > 0){
			foreach(@{$actions->{'pipeto'}}){
				_error("Can't configure mailbox pipe for '$emailAddress' : $_");
				push(@{$messages->{'mailboxpipe'}}, "$emailAddress: $_") if($_ =~ /.+/);
			}
			if(scalar($actions->{'unknown'})>0){
				foreach(@{$actions->{'unknown'}}){
					push(@{$messages->{'domainunknown'}}, "domainName: $_") if($_ =~ /.+/);
				}
			}
		}
		my $mailbox = $domain->{'mailboxes'}{$emailAddress};
		$mailbox->{'name'} = $emailAddress;
		$mailbox->{'actions'} = processActions($mailbox->{'actions'});
		configureUser($mailbox);
	}
}

dumpPasswords($generatedPasswords,$f_passwords);

print "Some config wasn't processed:\n";
print "Domains with unhandled pipes in .qmail-default:\n";
print "\t";
print join("\n\t", @{$messages->{'domainpipe'}});
print "\n\n";
print "All Done!\n";
exit 0;


# # # # # #
# # # # #
# # # #
# # #
# #
#

# Given an $actions hashref attempts to translate them into
# postfixisms. Particularly:
#  - pipes to vdelivermail are changed to forwards
#  - pipes to vdelivermail that simply delete mail are ignored
#  - unhandled pipes produce errors
#TODO:
#  - absoulte paths to mailboxes will be converted into forwards

sub processActions{
	my $actions = shift;
	foreach my $action (keys(%{$actions})){
		if(scalar(@{$actions->{$action}}) > 0){
			# Actions are 'forwardto', 'pipeto', 'deliverto' and 'unknown'
			# targets are their contents, literally the lines out of .qmail-*
			foreach my $target (@{$actions->{$action}}){
				if($action =~ /pipeto/){
					if ($target =~ /vdelivermail '' delete/){
						$target = "";
						next;
					}
					#See if vdelivermail is being used to effect a forwarder:
					if( my @matches = ($target =~ m#vdelivermail '' .+domains/(\d+/)?(.+)/(.+)$#)){
						my $to = $matches[-1].'@'.$matches[-2];
						print "     Set forwarder to $to\n" if $verbosity > 1;
						push(@{$actions->{'forwardto'}}, $to);
						$target = "";
						next;
					}
					if($target =~ /vdelivermail '' (.+@.+)\s*$/){
						my $to = $1;
						print "     Setting forwarder to $to\n" if $verbosity > 1;
						push(@{$actions->{'forwardto'}}, $to);
						$target = "";
						next;
					}
				}
			}
		}
	}
	return $actions;
}

# Creates and returns a password:
sub generatePassword {
	my $pwgen = shift;
	my $pw = `pwgen 10 1 2>/dev/null`;
	chomp $pw;
	return $pw;
}
# Accepts a hashref as an argument which defines the
# user to be configured (set up as normal, or as an 
# alias)
sub configureUser {
	my $mailbox = shift;
	my $emailAddress = $mailbox->{'name'};
#	if(scalar($mailbox->{'actions'}{'forwardto'}) > 0){
#		my $target = join(" ", $mailbox->{'actions'}{'forwardto'});
#		$p->createAliasDomain(
#			target => $target,
#			alias  => $emailAddress,
#		);
#		# If this domain needs to forward to itself then
#		# we need to carry on and create it. Else, we can
#		# leave here.
#		return unless ($target =~ /$emailAddress/);
#	}
	

	# Deal with passwords:
	my $pw;
	if($mailbox->{'plain'} =~ /.+/){
		$pw = $mailbox->{'plain'};
		if($verbosity > 9){
			print "     using password '".$mailbox->{'plain'}."'\n";
		}elsif($verbosity > 3){
			print "     using known password\n";
		}
	}else{
		#Generate a password:
		$pw = generatePassword($pwgen);
		push(@{$messages->{'nopassword'}}, $mailbox->{'name'});
		$generatedPasswords->{$emailAddress} = $pw;
		if($verbosity > 0){
			print "     created password '$pw'\n";
		}elsif($verbosity > 3){
			print "     created password\n";
		}
	}
	my $quota = convertQuota($mailbox->{'quota'});
	print "     setting quota to $quota\n" if $verbosity > 3;
	$p->createUser(
		username => $emailAddress,
		password_clear => $pw,
		name => $mailbox->{'comment'},
		quota => $quota,
	);
}

# prints generated passwords to file:
sub dumpPasswords{
	my $passwords = shift;
	my $f_password = shift;
	my $fh;
	eval{
		open($fh, ">", $f_password) or die "Error opening password file '$f_password' : $!";
	};
	if ($@){
		print STDERR $@;
		print "Will dump passwords to stdout instead\n";
		$fh = \*STDOUT;
	}
	foreach my $emailAddress (sort((keys(%{$passwords})))){
		my $pw = $passwords->{$emailAddress};
		print $fh "$emailAddress $pw\n";
	}
	close($fh);

}

# Accepts a hashref as an argument which defines the
# domain to be configured (set up as normal, or as an
# alias)
sub configureDomain {
	my $domain = shift;
	my $domainName = $domain->{'name'};
	return if $p->domainExists($domainName);

	if($domain->{'aliases'} > 0){
		my $targets = join(" ", @{$domain->{'aliases'}});
		$p->createAliasDomain(
			target => $targets,
			alias  => $domainName,
		);
		print "  $domainName is an alias for $targets\n";
	}else{
		$p->createDomain(
			domain => $domainName,
		);
	}
}

# Postfixadmin wants the quota in bytes, but
# vpopmail stores it in human-friendly (and
# base-10) values. It also uses the string 
# 'NOQUOTA' whereas pfa uses the value zero.
sub convertQuota{
	my $quota = shift;
	if ($quota =~ /(\d+)G/i){
		$quota = $1 * 1e9;
	}elsif ($quota =~ /(\d+)M/i){
		$quota = $1 * 1e6;
	}elsif($quota =~ /(\d+)K/i){
		$quota = $1 * 1e3;
	}elsif($quota =~ /^NOQUOTA$/){
		$quota = 0;
	}
	return $quota;
}

# non-fatal errors:
sub _error {
	return unless $verbosity > 0;
	my $message = shift;
	chomp $message;
	print STDERR $message."\n";
}

sub usage(){

print <<EOF;
import.pl , part of vpopmail2postfixadmin

usage:

	import.pl <options> -f <file>

Options:
        -d              Dry run; do everything except that which
                        involves writing to the db.
        -f <file> 	Read from <file> for config data. 
        -g <expr>       evaluate expr to generate passwords where 
	                necessary (see below). Is executed in the 
                        shell, not perl. Default: `$pwgen`
        -h              Show this help
        -p <file>       Write generated passwords to <file>
                        Default: $f_passwords
        -v <num>        Set verbosity to num, will print:
                        1 : Non-fatal errors
                        2 : Name of each domain configured
                        3 : Username of each user configured
                        4 : Parameters used for each domain and 
                            user (except passwords)
                        9 : Clear-text passwords of each user

Verbosity is cumulative - setting it to 3 will enable 2 and 1, 
too. That which is printed at 1 is printed to STDERR, 
irrespective of higher numbers (which go to STDOUT).

Users in the supplied config with no clear-text passwords have
one generated for them using the parameter to -g (or its 
default) these usernames and their auto-generated passwords 
written to the password file specified by -p (or its default).

EOF
exit 1;
}
