#! /usr/bin/perl

# import.pl; part of vpopmail2postfixadmin
#
# Imports the dump produced by export.pl, and uses it to configure
# postfixadmin.

##Todo: strict-compatible version of `my %config = %{eval $dump};`


#use strict;

use lib '/home/avi/bin/vpostmail';

use Data::Dumper;
#use Mail::Postfixadmin;
use Getopt::Std;
use YAML qw/LoadFile/;
my %o;
my %options;

getopts('dv:f:g:p:', \%options);
$o{verbose} = $options{v} || 2;
my $file = $options{f};
my $passwordFile = $options{p} || "./passwords";
my $pwgen = $options{g} || 'pwgen 10 1';
$o{dryrun} = 3 if exists($options{d});

if ( exists($options{h}) || $file =~ /^$/){
	usage();
}

# Import the dump:
$/ = undef;
#open(my $f, "<", $file);
#my %config = %{eval <$f>};
my %config = LoadFile($file);

print Dumper(%config);
exit;

open(my $pwfile, ">", $passwordFile) or die "Error opening password file $passwordFile";

#my $v = Mail::Postfixadmin->new(
#	mysqlconf => '/home/avi/bin/.vmail.mysql.conf',
#	storeCleartextPassword => 1,
#);

#Verbosity:
#1: can't-configures only (stdout)
#2: 1 + domains
#3: 2 + email addresses
#4: 3 + params
#5: 4 + 
#9: 5 + clear passwords(!?)
select STDOUT;
local $| = 1;
foreach my $domain (keys(%config)){
	print "Configuring $domain\n" if $o{verbose} > 1;
	$v->setDomain($domain);
	$v->createDomain unless $v->domainExists || exists($o{dryrun});
	foreach my $alias (@{$config{$domain}{aliases}}){
		print "  -> creating $alias as an alias of $domain\n" if $o{verbose} > 1;
		$v->createAliasDomain(target => $alias) unless exists($o{dryrun});
	}
	foreach my $email (keys(%{$config{$domain}})){
		print "\tConfiguring $email\n" if $o{verbose} > 2;
		if ($email =~ /\@/){
			my %emailConfig = %{$config{$domain}{$email}};
			my @dotqmail = @{$emailConfig{dotqmail}};
			my $quota = $emailConfig{quota};
			my $plain = $emailConfig{plain};
			my $comment = $emailConfig{comment};
			my @forwardto = @{$emailConfig{forwardto}};

			# let's convert the quota into bytes for Dovecot, 
			# remembering that in qmail 1K = 1000, not 1024
			if ($quota =~ /(\d+)G/i){
				$quota = $1 * 1e9;
			}elsif ($quota =~ /(\d+)M/i){
				$quota = $1 * 1e6;
			}elsif($quota =~ /(\d+)K/i){
				$quota = $1 * 1e3;
			}elsif($quota =~ /^NOQUOTA$/){
				$quota = 0;
			}
			if (($verbosity > 0) && ($dotqmail[0] =~ /.+/)){
				foreach(@dotqmail){
					if($verbosity < 2){
						print STDERR "$email : $_\n";
					}else{
						print STDERR "Can't configure: $_\n";
					}
				}
			}


			$v->setUser($email);
			if ($forwardto[0]=~/\@/){
				$v->createAliasUser(target => [@forwardto]) unless(exists($o{dryrun}));
				print "\t  -> forwards to $forwards\n" if $o{verbose} > 2;
			}else{
				unless ($v->userExists && (!exists($o{dryrun}))){
					$v->createUser(
						quota => $quota,
						created => $v->now(),
						modified => $v->now(),
						active => 1,
					);
				}
				if ($plain =~ /^$/){
					$plain = qx/$pwgen/;
					print $pwfile "$user:$plain\n";
				}
				chomp $plain;
				print "\t  ->Setting password to $plain\n" if $o{verbose} > 8;
				$v->changePassword($plain) unless(exists($o{dryrun}));
			}
		}
	}
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
                        Default: $passwordFile
        -v <num>        Set verbosity to num, will print:
                        1 : Only those lines from .qmail files
                            that I don't understand
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
