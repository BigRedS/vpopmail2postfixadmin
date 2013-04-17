#! /usr/bin/perl


use strict;

use 5.010;

use Mail::Postfixadmin;

use Data::Dumper;
use Getopt::Std;
use File::Copy;
use YAML qw/LoadFile/;
my %o;

# Options:
# f: supply a yaml file
# r: path to rsync daemon
# o: rsync options
# h: host from which to sync the mail
# u: user to connect as
# m: only do this mailbox
# U: don't switch to vmail user
getopts('f:h:r:O:m:U', \%o);

my $f_yaml = $o{'f'} || _error("No file supplied (use -f)");
my $rsyncBinary = $o{'r'} || `which rsync` ; chomp $rsyncBinary;
my $rsyncOptions = $o{'O'} || "avz";
my $rsyncHost = $o{'h'} || _error("No host supplied (use -f)");
my $rsyncUser = $o{'u'} || getpwuid($<);
my $dontSwitchUser = $o{'U'} || undef;

$rsyncHost = $rsyncUser."@".$rsyncHost;
$rsyncOptions = "-".$rsyncOptions;

my %config = LoadFile($f_yaml);

my $pfa = Mail::Postfixadmin->new();

# Put together all the rsync commands we're going to need to 
# run. Print out the first few in the hope that a user will
# spot anything obviously wrong
my @rsyncs = getRsyncCommands(%config);
_info("First few maildirs:");
foreach(qw/0 1 2 3/){
	_info("   ".@rsyncs[$_]->[3]) if exists $rsyncs[$_];
}

# Get the UID and GUID as which Postfix runs, in order that
# we can later su to this and so write the mail as if postfix
# were (and, hence, trip over any obvious pitfalls on the way)
my($uid,$gid) = getPostfixUid();
_info("PostfixAdmin UID/GID: $uid/$gid");

syncMailboxes(@rsyncs);

# # # #
# # #
# #
#


sub renameDovecotIndexes{
	my $d_mailbox = shift;
	opendir(my $dh, $d_mailbox) or _warn ("Can't open mailboxdir '$d_mailbox' to tidy indexes:: $!") and return;
	my @indexes = grep{/^dovecot.index/} readdir($dh);
	foreach my $file (@indexes){
		my $newName = "_".$file;
		move($d_mailbox."/".$file, $d_mailbox."/".$newName);
	}
}


# Mailfiles in maildirs store the size of the file in the 
# filename, as an S=<size> , but this is inconsistent and
# non-standard. For now, we just strip the size and so force
# dovecot to stat() it on next access.
# We do new before cur since mail moves in that direction, too
# - if an mail is read we're iterating through 'new' we'll see
# it when we do cur.
# We don't touch tmp because it's impolite to.
sub renameMailFiles{
	my $d_mailbox = shift;
	foreach (qw/new cur/){
		my $d_subMaildir = $d_mailbox."/".$_;
		opendir(my $dh_subMaildir, $d_subMaildir) or _warn("Can't open mailboxdir '$d_mailbox' to rename files:: $!") and return;
		my @files = grep{/,.+S=\d+/} readdir($dh_subMaildir);
		foreach my $file (@files){
			my $newFile = $file;
			$newFile =~ s/S=\d+//;
			my $file = $d_subMaildir."/".$file;
			my $newFile = $d_subMaildir."/".$newFile;
			if(-f $file){
				move($file,$newFile);
			}
		}
	}
}

sub syncMailboxes{
	my @rsyncs = @_;
	unless($dontSwitchUser){
		$> = $uid;
		$< = $gid;
	}
	_info("Running rsync as user: ".getpwuid($<)." ($</$>)");
	foreach my $cmd (@rsyncs){
		my $mailbox = $cmd->[3];
		`mkdir -p $mailbox`;
		_info("CMD: ", @{$cmd});
		my $output = system(@{$cmd});
		renameMailFiles($mailbox);
		renameDovecotIndexes($mailbox);
		`chown $uid:$gid $mailbox/.. -R`;
	}
}

sub getRsyncCommands{
	my %config = @_;
	my @rsyncs;
	if(exists($o{'m'})){
		if($o{'m'} =~ /@(.+)$/){
			my $domain = $1;
			_error("$o{'m'} isn't configured in config file")	unless my $srcDir = $config{$domain}->{'mailboxes'}->{$o{'m'}}->{'dir'}."/Maildir/";
			my $destDir = getDestDir($o{'m'});
			my @rsyncCmd = ($rsyncBinary, $rsyncOptions, "$rsyncHost:$srcDir", $destDir);
			push(@rsyncs, \@rsyncCmd);
		}else{
			_error("'$o{'m'}' doesn't look like an email address");
		}
	}else{
		foreach my $domain (keys(%config)){
			foreach my $mailbox (keys(%{$config{$domain}->{'mailboxes'}})){
				my $srcDir = $config{$domain}->{'mailboxes'}->{$mailbox}->{'dir'}."/Maildir";
				my $destDir = getDestDir($mailbox);
				my @rsyncCmd = ($rsyncBinary, $rsyncOptions, "$rsyncHost:$srcDir", $destDir);
				push(@rsyncs, \@rsyncCmd);
			}
		}
	}
	return @rsyncs;
}

# If postfix and Dovecot disagree, side with Postfix since that's where other 
# incoming mail will be delivered to. 
sub getDestDir{
	my $username = shift;
	my $mailboxInfo = $pfa->getMailboxInfo($username);
	my $path;
	if(ref($mailboxInfo->{'path'}) eq "HASH"){
		return $mailboxInfo->{'path'}->{'postfix'};
	}else{
		return $mailboxInfo->{'path'};
	}
}
		

sub getPostfixUid{
	my $uid = (split(/:/, $pfa->{'_postfixConfig'}->{'virtual_uid_maps'}))[1];
	my $gid = (split(/:/, $pfa->{'_postfixConfig'}->{'virtual_gid_maps'}))[1];
	return $uid,$gid;
}

sub _warn{
	say "WARN:  ". join(" ", @_);
#	push(@problems, \@_);
}

sub _error{
	say "ERROR: ". join(" ", @_);
	exit 1;
}
sub _info{
	say join(" ", @_);
}