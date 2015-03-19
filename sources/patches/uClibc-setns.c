The setns system call is only 5 years old, so uClibc can't be expected to support it, but toybox needs it.

--- /dev/null	2015-03-12 00:35:23.675793740 -0500
+++ uClibc/libc/sysdeps/linux/common/setns.c	2015-03-19 13:18:05.711157730 -0500
@@ -0,0 +1,3 @@
+#include <sys/syscall.h>
+
+_syscall2(int, setns, int, fd, int, nstype);
