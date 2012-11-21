#!/usr/bin/perl

# -----------------------------------------------------------------------------
# logfiles2syslog.pl
# Patrick Viet 2012 - patrick.viet@gmail.com
# GITHUB PUBLIC REPO: http://github.com/patrickviet/logfiles2syslog
#
# USAGE: ./logfiles2syslog.pl [<config file>]
# Default config file: /etc/logfiles2syslog.conf
#
# Config file format (good old windows ini-style)
# 
# [base]
# includedir = /etc/logfiles2syslog.conf.d/
# rewatch_interval = 100
# rewatch_interval_on_error = 10
#
# [sometag]
# watchdir = /path/to/dir
# watchpattern = .log
#
# # if you want to watch a single file
# # internally, it actually just sets the directory to base, and the pattern
# # to the file name
# [someothertag]
# watchfile = /some/log/file.log
#
# -----------------------------------------------------------------------------
# include files:
# it will use the base of the filename as a section name,
# ie. myapp.conf with watchdir = /my/app
# is equivalent to having [myapp], watchdir = /my/app in the main config file
#
# -----------------------------------------------------------------------------

use warnings;
use strict;
use Linux::Inotify2;
use POE;
use Fcntl qw(:seek);
use Config::Tiny;

$| = 1;

# -----------------------------------------------------------------------------
# INIT
#
# command line
my $cfile = '/etc/logfiles2syslog.conf';
if (scalar @ARGV) {
	$cfile = shift @ARGV;
}

# build inotify and stuff

my $inotify = new Linux::Inotify2
	or die "unable to create Inotify object: $?";
$inotify->blocking(0);

my %dirs = ();
my %watchers = ();
my %openfiles = ();

# load config
my $conf;
my $firstload = 1;
sub loadconfig {
	my $newconf;
	my %newdirs = ();
	eval {
		$newconf = Config::Tiny->read($cfile) or die "unable to open file $cfile: ".Config::Tiny->errstr;

		die "no \[base\] section in config file $cfile" unless exists $newconf->{base};
		foreach (qw(rewatch_interval rewatch_interval_on_error includedir)) {
			die "$_ param absent from \[base\]" unless exists $newconf->{base}->{$_};
			die "$_ param unset in \[base\]" if $newconf->{base}->{$_} eq '';
		}

		foreach(qw(rewatch_interval rewatch_interval_on_error)) {
			die "param $_ is not numeric integer" if $newconf->{base}->{$_} =~ m/[^0-9]/;
		}

		my $incdir = $newconf->{base}->{includedir};
		die "no such include directory $incdir in $cfile" unless -d $incdir;

		## load main section
		foreach(keys %$newconf) {
			next if $_ eq 'base';
			die "you can't put params with no section in $cfile" if $_ eq '_';

			# 1st part duplicate code
			my $sectionconfig = loadconfig_section($_,$newconf->{$_});
			my ($dir,$pattern) = @$sectionconfig;
			die "double config for directory $dir" if exists $newdirs{$dir};
			$newdirs{$dir} = $pattern;

		}

		## load other sections
		opendir(my $dh, $incdir) or die "unable to open include dir $incdir specified in $cfile";
		foreach(readdir $dh) {
			next unless m/(.*)\.conf$/;
			my $namebase = $1;
			my $incfile = "$incdir/$_";
			next unless -f $incfile;

			my $newsection = Config::Tiny->read($incfile) or die "unable to read include file $incfile";
			foreach(keys %${newsection}) {
				my $name = $namebase;
				if($_ ne '_') { $name = $namebase.'_'.$_; }

				# this is duplicate code but whatever it's only 4 lines
				my $sectionconfig = loadconfig_section($name,$newsection->{$_});
				my ($dir,$pattern) = @$sectionconfig;
				die "double config for directory $dir" if exists $newdirs{$dir};
				$newdirs{$dir} = $pattern;
			}

		}
		closedir($dh);
	};

	if ($@) {
		if ($firstload) {
			die "unable to init app, dying: $@";
		} else {
			warn "unable to reload newconf - keeping old conf: $@"; return;
		}
	}

	$conf = $newconf;

	# unwatch directories that don't exist anymore
	foreach(keys %dirs) {
		if(!exists $newdirs{$_}) {
			$watchers{$_}->cancel;
			print "configuration change: not watching $_ anymore\n";
		}
	}

	foreach(keys %newdirs) {
		if(!exists $dirs{$_}) {
			print "configuration change: adding a watch to $_ with pattern ".$newdirs{$_}."\n";
		}
	}

	%dirs = %newdirs;

	# close files that don't match anymore
	foreach (keys %openfiles) {
		m/(.*)\/([^\/]+)$/;
		my ($dir,$file) = ($1,$2);
		if(exists $dirs{$dir}) {
			my $pattern = $dirs{$dir};
			if(!$file =~ m/$pattern$/) {
				# doesnt match pattern anymore
				my $fh = delete $openfiles{$_};
				close $fh;
			}
		} else {
			my $fh = delete $openfiles{$_};
			close $fh;
		}
	}

}

sub loadconfig_section {
	my ($name,$section) = @_;
	# we are looking for watchdir/watchpattern OR watchfile
	if(exists $section->{watchfile}) {
		die "you must choose watchdir/watchpattern or just watchfile in section $name"
			if exists $section->{watchdir} or exists $section->{watchpattern};

		die "non existent file ".$section->{watchfile}." specified in section $name" unless -f $section->{watchfile};
		# try to open it just to be sure
		open TESTOPEN, $section->{watchfile} or die "unable to open file ".$section->{watchfile}." specified in section $name: $!";
		close TESTOPEN;

		$section->{watchfile} =~ m/(.*)\/([^\/]+)$/;
		@{$section}{'watchdir','watchpattern'} = ($1,$2); # weird syntax eh?
	}

	foreach(qw(watchdir watchpattern)) { die "no $_ param in section $name" unless exists $section->{$_}; }

	die "non existent directory ".$section->{watchdir}." specified in section $name" unless -d $section->{watchdir};
	die "no pattern specified in section $name" unless $section->{watchpattern};

	# I prefer to return a ref to a table rather than an actual table, its less messy
	return [ $section->{watchdir}, $section->{watchpattern} ];

}

loadconfig();
$firstload = 0;

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

	# FIXME: must check for race condition where this happens
	# a file has been closed because it's not watched anymore, but
	# it get a notification that happened during the close

	# according to documentation it empties the queue though...

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
		'sighup' => \&sighup,
		'reload' => \&reload,
	}
);

sub start {
	#print "starting\n";
	my $kernel = $_[KERNEL];
	open my $inotify_FH, "< &=" . $inotify->fileno or die "Can’t fdopen: $!\n";
	$kernel->sig('HUP','sighup');
	$kernel->select_read($inotify_FH,'ev');
	$kernel->yield('watchdirs');
}

sub sighup {
	my $kernel = $_[KERNEL];
	print "got HUP signal - triggering reload\n";
	$kernel->sig_handled();
	$kernel->yield('reload');
}

sub reload {
	my $kernel = $_[KERNEL];
	loadconfig();
	$kernel->yield('watchdirs',1);
}
sub watchdirs {
	my ($kernel,$runonce) = @_[KERNEL,ARG0];
	#print "watchdirs\n";
	my $err = 0;
	foreach my $dir (keys %dirs) {
		my $pattern = $dirs{$dir};
		if (opendir(my $dh,$dir)) {
			foreach(readdir $dh) {
				if(m/$pattern$/) {
					# it's a log file
					my $fullname = "$dir/$_";
					tailfile($fullname);

				}
			}
		} else {
			print "error opening directory $dir: $!\n";
			$err = 1;
		}

		# I can watch multiple times without consequence
		# inotify_add_watch(7) says that:
		# "If pathname was already being watched, then the descriptor for the existing watch is returned"

		my $watcher = $inotify->watch($dir, IN_MODIFY | IN_DELETE);
		$watchers{$dir} = $watcher;
		
	}
	$kernel->delay_set('watchdirs',$err?$conf->{base}->{rewatch_interval_on_err}:$conf->{base}->{rewatch_interval})
		unless $runonce;
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

			# lets just check what the pattern match is
			my $watcher = $ev->w;
			my $dir = $watcher->name;
			my $pattern;
			if(exists $watchers{$dir} and exists $dirs{$dir}) {
				$pattern = $dirs{$dir};
			} else {
				$watcher->cancel;
				delete $dirs{$dir};
				delete $watchers{$dir};
				warn "RED FLAG: event for dir $dir ignored because not in conf";
				$kernel->yield('watchdirs');
				next;
			}

			if($ev->name =~ m/$pattern$/) {
				# we're ignoring other files

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
