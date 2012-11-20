logfiles2syslog
===============

inotify based perl tool that logs files and pushes their content to syslog


Requirements
------------

(Debian/Ubuntu) : base perl + Linux::Inotify2 + POE + Config::Tiny
apt-get install liblinux-inotify2-perl libpoe-perl libconfig-tiny-perl

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
echo "/usr/local/bin/logfiles2syslog.pl" >> /root/logfiles2syslog.run
chmod +x /root/logfiles2syslog.run
mv /root/logfiles2syslog.run /etc/service/logfiles2syslog/run

