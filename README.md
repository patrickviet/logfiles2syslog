logfiles2syslog
===============

inotify based perl tool that logs files and pushes their content to syslog

Licence
-------
BSD licence. Basically I guarantee nothing, and you can do what you want with it, as long as you give me credit, keep this notice, don't say you made it or use my name/the name of the product to endorse something you made.

Requirements
------------

This only runs on Linux with inotify (2.6.13 and onwards - anything released after 2005 should be OK)
It does NOT run on MacOSX, xBSD or Windows. Adapt it if you want to use kqueue

(Debian/Ubuntu) : base perl + Linux::Inotify2 + POE + Config::Tiny
apt-get install liblinux-inotify2-perl libpoe-perl libconfig-tiny-perl

Obviously it also run just the same on any kind of Linux such as Red Hat, CentOS, ...
I just don't know the names of the packages

Configuration
-------------

For now just files /etc/logfiles2syslog.conf and /etc/logfiles2syslog.d/*.conf
They contain a list of directories in which to watch *.log, within sections
(FIXME: will add some extra pattern matching options)

Installation
------------

Copy file to /usr/local/bin/logfiles2syslog.pl (don't forget chmod 755)
Copy base config file to /etc/logfiles2syslog.conf
Create directory /etc/logfiles2syslog.conf.d/
Put any extra something.conf file in this directory /etc/logfiles2syslog.conf.d/
Run

Then run it with some kind of daemon wrapper, ie. runit
apt-get install runit
mkdir /etc/service/logfiles2syslog
echo "#!/bin/sh" > /root/logfiles2syslog.run
echo "/usr/local/bin/logfiles2syslog.pl | logger -t logfiles2syslog" >> /root/logfiles2syslog.run
chmod +x /root/logfiles2syslog.run
mv /root/logfiles2syslog.run /etc/service/logfiles2syslog/run

Real life usage example with the RAILO Java Coldfusion interpreter
------------------------------------------------------------------

Railo writes logs in appdir/WEB-INF/logs/
You can change the directory, but you can't change the fact that it's log files

So here is appropriate config:

FILE: /etc/logfiles2syslog.conf.d/myrailoapp.conf
watchdir = /srv/www/mysite/WEB-INF/logs
watchpattern = .log

And ... that's it
You can now use syslog options and so on to be able to distribute railo logs to a central server.
