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
use Getopt::Std;
my %o;
$o{dryrun} = 3;
$o{verbose} = 1;
my %options;

getopts('dv:f:', \%options);
$o{verbose} = $options{v};
my $file = $options{f};

# Import the dump:
#y $file = $ARGV[0];
$/ = undef;
open(my $f, "<", $file);
#my $dump = <$f>;
#close($f);
my %config = %{eval <$f>};

# Create a vpostmail object:
my $v = Vpostmail->new(
	mysqlconf => '/home/avi/bin/.vmail.mysql.conf',
	storeCleartextPassword => 1,
);

#erbosity:
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
						print "$email : $_\n";
					}else{
						print "Can't configure: $_\n";
					}
				}
			}


			$v->setUser($email);
			if ($forwardto[0]=~/.+/){
				$forwards = join(/, /, @forwardto);
				$v->createAliasUser(target => $forwards) unless(exists($o{dryrun}));
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
				print "\t  ->Setting password to $plain\n" if $o{verbose} > 8;
				$v->changePassword($plain) unless(exists($o{dryrun}));
			}
		}
	}
}


