#!/usr/bin/perl

# -----------------------------------------------------------------------------
# logfiles2syslog.pl
# Patrick Viet 2012 - patrick.viet@gmail.com
# http://github.
# -----------------------------------------------------------------------------

use warnings;
use strict;
use Sys::Syslog qw( :DEFAULT setlogsock );
use Linux::Inotify2;
use POE;
use Fcntl qw(:seek);
use Config::Tiny;

# -----------------------------------------------------------------------------
# INIT
setlogsock('unix');
openlog('filedump', 'cons', 'notice');

my $inotify = new Linux::Inotify2
	or die "unable to create Inotify object: $?";
$inotify->blocking(0);

my @dirs = ();
my %openfiles = qw();
#my $filematch = m/\.log$/;

sub reloadconfig {
	open FILE,"/etc/logfiles2syslog.conf";
}

# -----------------------------------------------------------------------------
# GENERIC LOOP
sub tailfile {
	my ($file,$noeof) = @_;

	if($noeof) {
		if(exists $openfiles{$file}) {
			my $fh = $openfiles{$file};
			if(eof($fh)) {
				print "no such file $file.. wtf?\n";
				close $openfiles{$file};
				delete $openfiles{$file};				
			}
		}
	}

	if(!exists $openfiles{$file}) {
		# lets open the file and tail it
		#print "open file $file\n";
		open (my $dh,$file); #fixme handle errors
		$openfiles{$file} = $dh;
		#print "opened file $file\n";

	}
	#print "read file $file\n";
	my $fh = $openfiles{$file};
	while(<$fh>) { print "$file: $_"; }
	seek($fh,0,SEEK_END);
}


POE::Session->create(
	inline_states => {
		'_start' => \&start,
		'ev' => \&ev_process,
		'watchdirs' => \&watchdirs,
	}
);

sub start {
	#print "starting\n";
	my $kernel = $_[KERNEL];
	open my $inotify_FH, "< &=" . $inotify->fileno or die "Can’t fdopen: $!\n";
	$kernel->select_read($inotify_FH,'ev');
	$kernel->yield('watchdirs');
}

sub watchdirs {
	my ($kernel,$runonce) = @_[KERNEL,ARG0];
	#print "watchdirs\n";
	my $err = 0;
	foreach my $dir (@dirs) {
		if (opendir(my $dh,$dir)) {
			foreach(readdir $dh) {
				if(m/\.log$/) {
					# it's a log file
					my $fullname = "$dir/$_";
					tailfile($fullname);

				}
			}
		} else {
			print "error opening directory $dir: $!\n";
			$err = 1;
		}
		$inotify->watch($dir, IN_MODIFY | IN_DELETE);
	}
	$kernel->delay_set('watchdirs',$err?10:100) unless $runonce;
}

sub ev_process {
	my $kernel = $_[KERNEL];
	my @events = $inotify->read;
	unless (@events > 0) {
		print "read error: $!";
		last ;
	}

	foreach my $ev (@events) {
		my $fullname = $ev->fullname;

		if (!$ev->IN_ISDIR) {

			if($fullname =~ m/\.log$/) {
				# only watch .log files

				if($ev->IN_MODIFY) {
					tailfile($fullname);
				}
				elsif($ev->IN_DELETE) {
					print "file $fullname was deleted. closing.\n";
					if(exists $openfiles{$fullname}) {
						close $openfiles{$fullname};
						delete $openfiles{$fullname};
					}
					$kernel->delay_set('watchdirs',5,1)

				}
				else {
					print "unhandled event\n";
				}
			}
		}	
	}

}



$poe_kernel->run;


=head

$inotify->watch('/var/log', IN_ALL_EVENTS);


while() {
	my @events = $inotify->read;
	unless (@events > 0) {
		print "read error: $!";
		last ;
	}
	foreach (@events) {

		print $_->fullname.' '.$_->name." ";

		if($_->IN_ACCESS) {
			print "IN_ACCESS\n";
		}
		elsif($_->IN_MODIFY) {
			print "IN_MODIFY\n";
		}
		elsif($_->IN_OPEN) {
			print "IN_OPEN\n";
		}
		elsif($_->IN_CLOSE_WRITE) {
			print "IN_CLOSE_WRITE\n";
		}
		elsif($_->IN_CLOSE_NOWRITE) {
			print "IN_CLOSE_NOWRITE\n";
		}
		elsif($_->IN_CREATE) {
			print "IN_CREATE\n";
		}
		elsif($_->IN_ISDIR) {
			print "IN_ISDIR\n";
		}
		else {
			print "UNWATCHED EVENT\n";
		}

		$inotify->watch('/var/log', IN_ALL_EVENTS) or die "unable to watch: $!";

	}
}