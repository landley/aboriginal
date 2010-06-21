/* vi: set sw=4 ts=4:
 *
 * oneit.c, tiny one-process init replacement.
 *
 * Copyright 2005, 2010 by Rob Landley <rob@landley.net>.
 */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/reboot.h>

char *console;
int poweroff;

// The minimum amount of work necessary to get ctrl-c and such to work is:
//
// - Fork a child (PID 1 is special: can't exit, has various signals blocked).
// - Do a setsid() (so we have our own session).
// - In the child, attach stdio to /dev/tty0 (/dev/console is special)
// - Exec the rest of the command line.
//
// PID 1 then reaps zombies until the child process it spawned exits, at which
// point it calls sync() and reboot().  I could stick a kill -1 in there.


int main(int argc, char *argv[])
{
  int i, args;
  pid_t pid;

  for (args=1; args<argc; args++) {
    if (*argv[args]=='-') switch (argv[args][1]) {
      case 'c':
        console=argv[++args];
        continue;
      case 'p':
        poweroff++;
        continue;
      default:
        args=argc;
        break;
    }
    break;
  }
  if (args>=argc) {
    fprintf(stderr,
      "usage: oneit [-p] [-c /dev/tty0] command [...]\n\n"
      "A simple init program that runs a single supplied command line with a\n"
      "controlling tty (so CTRL-C can kill it).\n\n"
      "-p\tPower off instead of rebooting when command exits.\n"
      "-c\tWhich console device to use.\n\n"
      "The oneit command runs the supplied command line as a child process\n"
      "(because PID 1 has signals blocked), attached to /dev/tty0, in its\n"
      "own session.  Then oneit reaps zombies until the child exits, at\n"
      "which point it reboots (or with -p, powers off) the system.\n");
    exit(1);
  }

  // Create a new child process.
  pid = vfork();
  if (pid) {
    chdir("/");

    // pid 1 just reaps zombies until it gets its child, then halts the system.
    while (pid!=wait(&i));
    sync();

    // PID 1 can't call reboot() because that syscall kills the task that calls
    // it, which causes the kernel to panic before the actual reboot happens.
    if (!vfork()) reboot(poweroff ? RB_POWER_OFF : RB_AUTOBOOT);
    sleep(5);
    _exit(1);
  }

  // Redirect stdio to /dev/tty0, with new session ID, so ctrl-c works.
  setsid();
  if (!console) console="/dev/tty0";
  for (i=0; i<3; i++) {
    close(i);
    if(-1==open(console, O_RDWR)) {
      fprintf(stderr, "Can't open '%s'\n", console);
      exit(1);
    }
  }

  execvp(argv[args], argv+args);
  _exit(127);
}
