// A little wrapper to figure out what commands you're actually using.

// To use it, you'll need to make a directory of symlinks and set up two
// environment variables.  Something like:
//
// export WRAPPY_LOGPATH=/path/to/wrappy.log
// export WRAPPY_REALPATH="$PATH"
//
// WRAPPYDIR=/path/to/wrappy
// cp wrappy $WRAPPYDIR
// for i in `echo $PATH | sed 's/:/ /g'`
// do
//   for j in `ls $i`
//   do
//     ln -s wrappy $WRAPPYDIR/$j
//   done
// done
//
// PATH="$WRAPPYDIR" make thingy

#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

char blah[65536];

int main(int argc, char *argv[], char *env[])
{
  char *logpath, *realpath, *p, *p2, *p3;

  int i, fd;

  // If these environment variables didn't propogate down to our build, how
  // did $PATH make it there?  (Faily noisily if they are missing...)

  logpath = getenv("WRAPPY_LOGPATH");
  realpath = getenv("WRAPPY_REALPATH");
  if (!logpath || !realpath) {
    fprintf(stderr, "No WRAPPY_%s\n", logpath ? "REALPATH" : "LOGPATH");
    exit(1);
  }

  // Figure out name of command being run.

  p2 = strrchr(*argv, '/');
  if (!p2) p2=*argv;
  else p2++;

  // Write command line to a buffer.  (We need the whole command line in one
  //buffer so we can do one write.)

  p=blah + sprintf(blah, "%s ",p2);
  for (i=1; i<argc && (p-blah)<sizeof(blah); i++) {
    *(p++)='"';
    for (p3 = argv[i]; *p3 && (p-blah)<sizeof(blah); p3++) {
      char *s = "\n\\\"", *ss = strchr(s, *p3);

      if (ss) {
        *(p++)='\\';
        *(p++)="n\\\""[ss-s];
      } else *(p++) = *p3;
    }
    *(p++)='"';
    *(p++)=' ';
  }
  p[-1]='\n';

  // Log the command line, using O_APPEND and an atomic write so this entry
  // always goes at the end no matter what other processes are writing
  // into the file.

  fd=open(logpath, O_WRONLY|O_CREAT|O_APPEND, 0777);
  write(fd, blah, p-blah);
  close(fd);

  // Touch the file that got used.

  // sprintf(blah, ROOTPATH "/used/%s", p2);
  // close(open(blah, O_WRONLY|O_CREAT, 0777));

  // Hand off control to the real executable

  for (p = p3 = realpath; ; p3++) {
    if (*p3==':' || !*p3) {
      char snapshot = *p3;
      
      *p3 = 0;
      snprintf(blah, sizeof(blah)-1, "%s/%s", p, p2);
      *p3 = snapshot;
      argv[0]=blah;
      execve(blah, argv, env);
      if (!*p3) break;
      p = p3+1;
    }
  }

  // Should never happen, means environment setup is wrong.
  fprintf(stderr, "Didn't find %s\n", p2);
  exit(1);
}
