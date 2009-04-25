#include <unistd.h>

// This is a more thorough version of setsid, which sets up both a session
// ID and a process group, and points the stdin signal handling to the new
// process group.

int main(int argc, char *argv[])
{
  setsid();
  setpgid(0,0);
  tcsetpgrp(0, getpid());
  if (argc>1) execvp(argv[1], argv+1);
  return 127;
}
