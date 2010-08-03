#!/bin/sh
#
# init.d script with LSB support for freenet-daemon.
#
# Please read this init.d carefully and modify the sections to
# adjust it to the program you want to run.
#
# Copyright (c) 2007 Javier Fernandez-Sanguino <jfs@debian.org>
# Copyright (c) 2009 Masayuki Hatta <mhatta@debian.org>
#
# This is free software; you may redistribute it and/or modify
# it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2,
# or (at your option) any later version.
#
# This is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License with
# the Debian operating system, in /usr/share/common-licenses/GPL;  if
# not, write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA 02111-1307 USA
#
### BEGIN INIT INFO
# Provides:          freenet-daemon
# Required-Start:    $network $local_fs $remote_fs
# Required-Stop:     $remote_fs	
# Should-Start:      $named
# Should-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Freenet REference Daemon
# Description:       Freenet is free software which lets you anonymously 
#                    share files, browse and publish "freesites" (web sites 
#                    accessible only through Freenet) and chat on forums, 
#                    without fear of censorship. Freenet is decentralised to 
#                    make it less vulnerable to attack, and if used in 
#                    "darknet" mode, where users only connect to their 
#                    friends, is very difficult to detect.
### END INIT INFO

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

DAEMON=/usr/bin/java            # Introduce the server's location here
NAME=freenet-daemon             # Introduce the short server's name here
DESC="Freenet REference Daemon" # Introduce a short description here
WORKDIR=/var/lib/freenet        # Working directory
LOGDIR=/var/log/freenet         # Log directory to use
PIDDIR=/var/run/freenet         # Run (pidfile) directory

PIDFILE=$PIDDIR/$NAME.pid       # Server pidfile
LOGFILE=$LOGDIR/$NAME.log       # Server logfile

test -x $DAEMON || exit 1

. /lib/lsb/init-functions

# Default options, these can be overriden by the information
# at /etc/default/$NAME
DAEMON_OPTS=""          # Additional options given to the server

DIETIME=10              # Time to wait for the server to die, in seconds
                        # If this value is set too low you might not
                        # let some servers to die gracefully and
                        # 'restart' will not work

STARTTIME=10            # Time to wait for the server to start, in seconds
                        # If this value is set each time the server is
                        # started (on start or restart) the script will
                        # stall to try to determine if it is running
                        # If it is not set and the server takes time
                        # to setup a pid file the log message might
                        # be a false positive (says it did not start
                        # when it actually did)

DAEMONUSER=freenet      # Users to run the daemons as. If this value
                        # is set start-stop-daemon will chuid the server

# Include defaults if available
if [ -f /etc/default/$NAME ] ; then
    . /etc/default/$NAME
fi

# Use this if you want the user to explicitly set 'RUN' in
# /etc/default/
if [ "x$RUN" != "xyes" ] ; then
    log_failure_msg "$NAME disabled, please adjust the configuration to your needs "
    log_failure_msg "and then set RUN to 'yes' in /etc/default/$NAME to enable it."
    exit 1
fi

# Check that the user exists (if we set a user)
# Does the user exist?
if [ -n "$DAEMONUSER" ] ; then
    if getent passwd | grep -q "^$DAEMONUSER:"; then
        # Obtain the uid and gid
        DAEMONUID=`getent passwd |grep "^$DAEMONUSER:" | awk -F : '{print $3}'`
        DAEMONGID=`getent passwd |grep "^$DAEMONUSER:" | awk -F : '{print $4}'`
    else
        log_failure_msg "The user $DAEMONUSER, required to run $NAME does not exist."
        exit 1
    fi
fi


set -e

running_pid() {
# Check if a given process pid's cmdline matches a given name
    pid=$1
    name=$2
    [ -z "$pid" ] && return 1
    [ ! -d /proc/$pid ] &&  return 1
    cmd=`cat /proc/$pid/cmdline | tr "\000" "\n"|head -n 1 |cut -d : -f 1`
    # Is this the expected server
    [ "$cmd" != "$name" ] &&  return 1
    return 0
}

running() {
# Check if the process is running looking at /proc
# (works for all users)

    # No pidfile, probably no daemon present
    [ ! -f "$PIDFILE" ] && return 1
    pid=`cat $PIDFILE`
    running_pid $pid $DAEMON || return 1
    return 0
}

start_server() {
# Start the process using the wrapper

        # Install freenodes.fref if not found
        if [ ! -f /etc/freenet/noderef/seednodes.fref ]; then
            cp /usr/share/freenet/seednodes.fref /etc/freenet/noderef/
        fi
        # Install freenet.ini if not found
        if [ ! -f /etc/freenet/freenet.ini ]; then
            cp /usr/share/freenet/freenet.ini /etc/freenet/
        fi

        # Set up $PIDDIR with the right permissions
        if [ ! -d $PIDDIR ]; then
            mkdir -p $PIDDIR || exit 1
        fi
        chown $DAEMONUSER:$DAEMONUSER $PIDDIR
        chmod 750 $PIDDIR

        if [ -z "$DAEMONUSER" ] ; then
            start_daemon -p $PIDFILE $DAEMON $DAEMON_OPTS $DAEMON_ARGS
            errcode=$?
        else
# if we are using a daemonuser then change the user id
            start-stop-daemon --start --quiet --background --nicelevel $NICE \
                        --make-pidfile --pidfile $PIDFILE \
                        --chuid $DAEMONUSER --chdir $WORKDIR \
                        --exec $DAEMON -- $DAEMON_OPTS -classpath /usr/lib/java/freenet-ext.jar:/usr/share/java/freenet-cvs-snapshot.jar freenet.node.NodeStarter /etc/freenet/freenet.ini
            errcode=$?
        fi
        return $errcode
}

stop_server() {
# Stop the process using the wrapper
        if [ -z "$DAEMONUSER" ] ; then
            killproc -p $PIDFILE $DAEMON
            errcode=$?
        else
# if we are using a daemonuser then look for process that match
            start-stop-daemon --stop --retry 5 --quiet --pidfile $PIDFILE \
                        --user $DAEMONUSER
	    rm -f $PIDFILE 
            errcode=$?
        fi

        return $errcode
}

reload_server() {
    [ ! -f "$PIDFILE" ] && return 1
    pid=pidofproc $PIDFILE # This is the daemon's pid
    # Send a SIGHUP
    kill -1 $pid
    return $?
}

force_stop() {
# Force the process to die killing it manually
    [ ! -e "$PIDFILE" ] && return
    if running ; then
        kill -15 $pid
        # Is it really dead?
        sleep "$DIETIME"s
        if running ; then
            kill -9 $pid
            sleep "$DIETIME"s
            if running ; then
                echo "Cannot kill $NAME (pid=$pid)!"
                exit 1
            fi
        fi
    fi
    rm -f $PIDFILE
}


case "$1" in
  start)
        log_daemon_msg "Starting $DESC " "$NAME"
        # Check if it's running first
        if running ;  then
            log_progress_msg "apparently already running"
            log_end_msg 0
            exit 0
        fi
        if start_server ; then
            # NOTE: Some servers might die some time after they start,
            # this code will detect this issue if STARTTIME is set
            # to a reasonable value
            [ -n "$STARTTIME" ] && sleep $STARTTIME # Wait some time 
            if  running ;  then
                # It's ok, the server started and is running
                log_end_msg 0
            else
                # It is not running after we did start
                log_end_msg 1
            fi
        else
            # Either we could not start it
            log_end_msg 1
        fi
        ;;
  stop)
        log_daemon_msg "Stopping $DESC" "$NAME"
        if running ; then
            # Only stop the server if we see it running
            errcode=0
            stop_server || errcode=$?
            log_end_msg $errcode
        else
            # If it's not running don't do anything
            log_progress_msg "apparently not running"
            log_end_msg 0
            exit 0
        fi
        ;;
  force-stop)
        # First try to stop gracefully the program
        $0 stop
        if running; then
            # If it's still running try to kill it more forcefully
            log_daemon_msg "Stopping (force) $DESC" "$NAME"
            errcode=0
            force_stop || errcode=$?
            log_end_msg $errcode
        fi
        ;;
  restart|force-reload)
        log_daemon_msg "Restarting $DESC" "$NAME"
        errcode=0
        stop_server || errcode=$?
        # Wait some sensible amount, some server need this
        [ -n "$DIETIME" ] && sleep $DIETIME
        start_server || errcode=$?
        [ -n "$STARTTIME" ] && sleep $STARTTIME
        running || errcode=$?
        log_end_msg $errcode
        ;;
  status)

        log_daemon_msg "Checking status of $DESC" "$NAME"
        if running ;  then
            log_progress_msg "running"
            log_end_msg 0
        else
            log_progress_msg "apparently not running"
            log_end_msg 1
            exit 1
        fi
        ;;
  # Use this if the daemon cannot reload
  reload)
        log_warning_msg "Reloading $NAME daemon: not implemented, as the daemon"
        log_warning_msg "cannot re-read the config file (use restart)."
        ;;
  # And this if it cann
  #reload)
          #
          # If the daemon can reload its config files on the fly
          # for example by sending it SIGHUP, do it here.
          #
          # If the daemon responds to changes in its config file
          # directly anyway, make this a do-nothing entry.
          #
          # log_daemon_msg "Reloading $DESC configuration files" "$NAME"
          # if running ; then
          #    reload_server
          #    if ! running ;  then
          # Process died after we tried to reload
          #       log_progress_msg "died on reload"
          #       log_end_msg 1
          #       exit 1
          #    fi
          # else
          #    log_progress_msg "server is not running"
          #    log_end_msg 1
          #    exit 1
          # fi
                                                                                    #;;

  *)
        N=/etc/init.d/$NAME
        echo "Usage: $N {start|stop|force-stop|restart|force-reload|status}" >&2
        exit 1
        ;;
esac

exit 0
