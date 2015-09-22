/* by Rob Landley <rob@landley.net>
 *
 * C compiler wrapper. Parses command line, supplies path information for
 * headers and libraries.
 *
 * This file is hereby released into the public domain.
 */

#undef _FORTIFY_SOURCE

#include <errno.h>
#include <libgen.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

// Default to musl
#ifndef DYNAMIC_LINKER
#define DYNAMIC_LINKER "/lib/libc.so"
#endif

// Some plumbing from toybox

void *xmalloc(long len)
{
  void *ret = malloc(len);

  if (!ret) {
    fprintf(stderr, "bad malloc\n");
    exit(1);
  }

  return ret;
}

// Die unless we can allocate enough space to sprintf() into.
char *xmprintf(char *format, ...)
{
  va_list va, va2;
  int len;
  char *ret;

  va_start(va, format);
  va_copy(va2, va);

  // How long is it?
  len = vsnprintf(0, 0, format, va);
  len++;
  va_end(va);

  // Allocate and do the sprintf()
  ret = xmalloc(len);
  vsnprintf(ret, len, format, va2);
  va_end(va2);

  return ret;
}

// Confirm that a regular file exists, and (optionally) has the executable bit.
int is_file(char *filename, int has_exe)
{
  // Confirm it has the executable bit set, if necessary.
  if (!has_exe || !access(filename, X_OK)) {
    struct stat st;

    // Confirm it exists and is not a directory.
    if (!stat(filename, &st) && S_ISREG(st.st_mode)) return 1;
  }
  return 0;
}

// Find a file in a colon-separated path
char *find_in_path(char *path, char *filename, int has_exe)
{
  char *cwd;

  if (index(filename, '/') && is_file(filename, has_exe))
    return strdup(filename);

  if (!path || !(cwd = getcwd(0, 0))) return 0;
  while (path) {
    char *str, *next = index(path, ':');
    int len = next ? next-path : strlen(path);

    if (!len) str = xmprintf("%s/%s", cwd, filename);
    else str = xmprintf("%.*s/%s", len, path, filename);

    // If it's not a directory, return it.
    if (is_file(str, has_exe)) {
      free(cwd);
      return str;
    } else free(str);

    if (next) next++;
    path = next;
  }
  free(cwd);

  return 0;
}

struct dlist {
  struct dlist *next, *prev;
  char *str;
};

// Append to end of doubly linked list (in-order insertion)
void dlist_add(struct dlist **list, char *str)
{
  struct dlist *new = xmalloc(sizeof(struct dlist));

  new->str = str;
  if (*list) {
    new->next = *list;
    new->prev = (*list)->prev;
    (*list)->prev->next = new;
    (*list)->prev = new;
  } else *list = new->next = new->prev = new;
}

// Some compiler versions don't provide separate T and S versions of begin/end,
// so fall back to the base version if they're not there.

char *find_TSpath(char *base, char *top, int use_shared, int use_static_linking)
{
  int i;
  char *temp;

  temp = xmprintf(base, top,
    use_shared ? "S.o" : use_static_linking ? "T.o" : ".o");

  if (!is_file(temp, 0)) {
    free(temp);
    temp = xmprintf(base, top, ".o");
  }

  return temp;
}


enum {
  Clibccso, Clink, Cprofile, Cshared, Cstart, Cstatic, Cstdinc, Cstdlib,
  Cverbose, Cx, Cdashdash, Cmelf,

  CPctordtor, CP, CPstdinc
};

#define MASK_BIT(X) (1<<X)
#define SET_FLAG(X) (flags |= MASK_BIT(X))
#define CLEAR_FLAG(X) (flags &= ~MASK_BIT(X))
#define GET_FLAG(X) (flags & MASK_BIT(X))

// Read the command line arguments and work out status
int main(int argc, char *argv[])
{
  char *topdir, *ccprefix, *dynlink, *cc, *temp, **keepv, **hdr, **outv;
  int i, keepc, srcfiles, flags, outc;
  struct dlist *libs = 0;

  if (getenv("CCWRAP_DEBUG")) fprintf(stderr, "%s@%s\n", argv[0], getcwd(0, 0));

  keepv = xmalloc(argc*sizeof(char *));
  flags = MASK_BIT(Clink)|MASK_BIT(Cstart)|MASK_BIT(Cstdinc)|MASK_BIT(Cstdlib)
          |MASK_BIT(CPctordtor);
  keepc = srcfiles = 0;

  if (getenv("CCWRAP_DEBUG")) {
    SET_FLAG(Cverbose);
    fprintf(stderr, "incoming: ");
    for (i=0; i<argc; i++) fprintf(stderr, "%s ", argv[i]);
    fprintf(stderr, "\n\n");
  }

  // figure out cross compiler prefix
  i = strlen(ccprefix = basename(*argv));
  if (i<2) {
    fprintf(stderr, "Bad name '%s'\n", ccprefix);
    exit(1);
  }
  if (!strcmp("++", ccprefix+i-2)) {
    cc = "raw++";
    SET_FLAG(CP);
    SET_FLAG(CPstdinc);
    if (i<3) exit(1);
    i -= 3;
  } else if (!strcmp("gcc", ccprefix+i-3)) i -= 3;   // TODO: yank
  else if (!strcmp("cc", ccprefix+i-2)) i-=2;
  else if (!strcmp("cpp", ccprefix+i-3)) {
    i -= 3;
    CLEAR_FLAG(Clink);
  } else return 1; // TODO: wrap ld
  if (!(ccprefix = strndup(ccprefix, (size_t)i))) exit(1); // todo: fix uclibc

  // Find the cannonical path to the directory containing our executable
  topdir = find_in_path(getenv("PATH"), *argv, 1);

  // Instead of realpath(), follow symlinks until we hit a real file or until
  // libc is available relative to this directory. (This way cp -s gives you
  // include and lib directories you can add stuff to, realpath() will drill
  // past snapshots to a "real" filesystem that may be read-only.)
  i = 99;
  while (topdir && i--) {
    char buf[4200], *new, *libc;
    int len;

    // If this isn't a symlink, we stop here.
    if (1 > (len = readlink(topdir, buf, 4096))) break;
    buf[len] = 0;

    // if we can find libc.so from here, stop looking.
    if (!(temp = strrchr(topdir, '/'))) break; // should never happen
    *temp = 0;
    libc = xmprintf("%s/../lib/libc.so", topdir);
    *temp = '/';
    len = access(libc, R_OK);
    free(libc);
    if (!len) break;

    // Follow symlink. Absolute symlink replaces, relative symlink appends
    if (buf[0] == '/') new = strdup(buf);
    else {
      temp = strrchr(topdir, '/');
      if (temp) *temp = 0;
      new = xmprintf("%s/%s", topdir, buf);
    }
    free(topdir);
    topdir = new;
  }

  if (!topdir || !(temp = strrchr(topdir, '/')) || strlen(*argv)<2) {
    fprintf(stderr, "Can't find %s in $PATH (did you export it?)\n", *argv);
    exit(1);
  }
  // We want to strip off the bin/ but the path we followed can end with
  // a symlink, so append .. instead.
  strcpy(++temp, "..");
  topdir = realpath(topdir, 0);

  // Add our binary's directory and the tools directory to $PATH so gcc's
  // convulsive flailing probably blunders through here first.
  // Note: do this before reading topdir from environment variable, because
  // toolchain binaries go with wrapper even if headers/libraries don't.
  temp = getenv("PATH");
  if (!temp) temp = "";
  temp = xmprintf("PATH=%s/bin:%s/tools/bin:%s", topdir, topdir, temp);
  putenv(temp);

  // Override header/library search path with environment variable?
  temp = getenv("CCWRAP_TOPDIR");
  if (!temp) {
    cc = xmprintf("%sCCWRAP_TOPDIR", ccprefix);

    for (i=0; cc[i]; i++) if (cc[i] == '-') cc[i]='_';
    temp = getenv(cc);
    free(cc);
  }
  if (temp) {
    free(topdir);
    topdir = temp;
  }

  // Name of the C compiler we're wrapping.
  cc = getenv("CCWRAP_CC");
  if (!cc) cc = "rawcc";

  // Does toolchain have a shared libcc?
  temp = xmprintf("%s/lib/libgcc_s.so", topdir);
  if (is_file(temp, 0)) SET_FLAG(Clibccso);
  free(temp);

  // Where's the dynamic linker?
  temp = getenv("CCWRAP_DYNAMIC_LINKER");
  if (!temp) temp = DYNAMIC_LINKER;
  dynlink = xmprintf("-Wl,--dynamic-linker,%s", temp);

  // Fallback library search path, these will wind up at the end
  dlist_add(&libs, xmprintf("%s/lib", topdir));
  dlist_add(&libs, xmprintf("%s/cc/lib", topdir));

  // Parse command line arguments
  for (i=1; i<argc; i++) {
    char *c = keepv[keepc++] = argv[i];

    if (!strcmp(c, "--")) SET_FLAG(Cdashdash);

    // is this an option?
    if (*c == '-' && c[1] && !GET_FLAG(Cdashdash)) c++;
    else {
      srcfiles++;
      continue;
    }

    // Second dash?
    if (*c == '-') {
      // Passthrough double dash versions of single-dash options.
      if (!strncmp(c, "-print-", 7) || !strncmp(c, "-static", 7)
          || !strncmp(c, "-shared", 7)) c++;
      else {
        if (!strcmp(c, "-no-ctors")) {
          CLEAR_FLAG(CPctordtor);
          keepc--;
        }
        continue;
      }
    }

    // -M and -MM imply -E and thus no linking.
    // Other -M? options don't, including -MMD
    if (*c == 'M' && c[1] && (c[1] != 'M' || c[2])) continue;

    // compile, preprocess, assemble... options that suppress linking.
    if (strchr("cEMS", *c))  CLEAR_FLAG(Clink);
    else if (*c == 'L') {
       if (c[1]) dlist_add(&libs, c+1);
       else if (!argv[++i]) {
         fprintf(stderr, "-L at end of args\n");
         exit(1);
       } else dlist_add(&libs, argv[i]);
       keepc--;
    } else if (*c == 'f') {
      if (!strcmp(c, "fprofile-arcs")) SET_FLAG(Cprofile);
#ifdef ELF2FLT
    } else if (*c == 'm') {
      if (!strcmp(c, "melf")) {
        SET_FLAG(Cmelf);
        keepc--;
      }
#endif
    } else if (*c == 'n') {
      keepc--;
      if (!strcmp(c, "nodefaultlibs")) CLEAR_FLAG(Cstdlib);
      else if (!strcmp(c, "nostartfiles")) {
        CLEAR_FLAG(CPctordtor);
        CLEAR_FLAG(Cstart);
      } else if (!strcmp(c, "nostdinc")) CLEAR_FLAG(Cstdinc);
      else if (!strcmp(c, "nostdinc++")) CLEAR_FLAG(CPstdinc);
      else if (!strcmp(c, "nostdlib")) {
        CLEAR_FLAG(Cstdlib);
        CLEAR_FLAG(Cstart);
        CLEAR_FLAG(CPctordtor);
      } else keepc++;
    } else if (*c == 'p') {
      if (!strncmp(c, "print-", 6)) {
        struct dlist *dl;
        int show = 0;

        // Just add prefix to prog-name
        if (!strncmp(c += 6, "prog-name=", 10)) {
          printf("%s%s\n", ccprefix, c+10);
          exit(0);
        }

        if (!strncmp(c, "file-name=", 10)) {
          c += 10;
          if (!strcmp(c, "include")) {
            printf("%s/cc/include\n", topdir);
            exit(0);
          }
        } else if (!strcmp(c, "search-dirs")) {
          c = "";
          show = 1;
          printf("install: %s/\nprograms: %s\nlibraries:",
                 topdir, getenv("PATH"));
        } else if (!strcmp(c, "libgcc-file-name")) {
          printf("%s/cc/lib/libgcc.a\n", topdir);
          exit(0);
        } else break;

        // Adjust dlist before traversing (move fallback to end, break circle)
        libs = libs->next->next;
        libs->prev->next = 0;

        // Either display the list, or find first hit.
        for (dl = libs; dl; dl = dl->next) {
          temp = dl->str;
          if (show) printf(":%s" + (dl==libs), dl->str);
          else {
            if (*c) temp = xmprintf("%s/%s", dl->str, c);
            if (!access(temp, F_OK)) break;
            if (*c) free(temp);
          }
        }
        if (dl) printf("%s", temp);
        printf("\n");

        return 0;
      } else if (!strcmp(c, "pg")) SET_FLAG(Cprofile);
    } else if (*c == 's') {
      keepc--;
      if (!strcmp(c, "shared")) {
        CLEAR_FLAG(Cstart);
        SET_FLAG(Cshared);
      } else if (!strcmp(c, "static")) {
        SET_FLAG(Cstatic);
        CLEAR_FLAG(Clibccso);
      } else if (!strcmp(c, "shared-libgcc")) SET_FLAG(Clibccso);
      else if (!strcmp(c, "static-libgcc")) CLEAR_FLAG(Clibccso);
      else keepc++;
    } else if (*c == 'v' && !c[1]) {
      SET_FLAG(Cverbose);
      printf("ccwrap: %s\n", topdir);
    } else if (!strncmp(c, "Wl,", 3)) {
#ifdef ELF2FLT
      // If user feeds in -Wl,-elf2flt= to set stack size, leave it to them
      if (strstr(c, ",-elf2flt")) SET_FLAG(Cmelf);
#endif
      temp = strstr(c, ",-static");
      if (temp && (!temp[8] || temp[8]==',')) {
        SET_FLAG(Cstatic);
        CLEAR_FLAG(Clibccso);
      }
      // This argument specifies dynamic linker, so we shouldn't.
      if (strstr(c, "--dynamic-linker")) dynlink = 0;
    } else if (*c == 'x') SET_FLAG(Cx);
  }

  // Initialize argument list for exec call (kept plus space for 64 new entries)
  outc = (keepc+64)*sizeof(char *);
  memset(outv = xmalloc(outc), 0, outc);
  outc = 0;
  outv[outc++] = cc;

  // Rewrite header paths (if compiling)
  if (srcfiles) {
    outv[outc++] = "-nostdinc";
    if (GET_FLAG(CP)) {
      outv[outc++] = "-nostdinc++";
      if (GET_FLAG(CPstdinc)) {
        outv[outc++] = "-isystem";
        outv[outc++] = xmprintf("%s/c++/include", topdir);
      }
    }
    if (GET_FLAG(Cstdinc)) {
      outv[outc++] = "-isystem";
      outv[outc++] = xmprintf("%s/include", topdir);
      outv[outc++] = "-isystem";
      outv[outc++] = xmprintf("%s/cc/include", topdir);
    }
  }

  // Rewrite library paths (if linking)
  if (srcfiles && GET_FLAG(Clink)) {
    // Zab defaults, add dynamic linker
    outv[outc++] = "-nostdlib";
    outv[outc++] = GET_FLAG(Cstatic) ? "-static" : dynlink;
    if (GET_FLAG(Cshared)) outv[outc++] = "-shared";

    // Copy libraries to output (first move fallback to end, break circle)
    libs = libs->next->next;
    libs->prev->next = 0;
    for (; libs; libs = libs->next)
      outv[outc++] = xmprintf("-L%s", libs->str);
    outv[outc++] = xmprintf("-Wl,-rpath-link,%s/lib", topdir); // TODO: in?
    // TODO: -fprofile-arcs
    if (GET_FLAG(Cprofile)) xmprintf("%s/lib/gcrt1.o", topdir);
    if (GET_FLAG(CPctordtor)) {
      outv[outc++] = xmprintf("%s/lib/crti.o", topdir);
      outv[outc++] = find_TSpath("%s/cc/lib/crtbegin%s", topdir,
                                 GET_FLAG(Cshared), GET_FLAG(Cstatic));
    }
    if (!GET_FLAG(Cprofile) && GET_FLAG(Cstart))
      outv[outc++] = xmprintf("%s/lib/%scrt1.o", topdir,
                              GET_FLAG(Cshared) ? "S" : "");
  }

  // Copy unclaimed arguments
  memcpy(outv+outc, keepv, keepc*sizeof(char *));
  outc += keepc;

  // Remaining standard link files (if linking)
  if (srcfiles && GET_FLAG(Clink)) {
    if (GET_FLAG(Cx)) outv[outc++] = "-xnone";
    if (GET_FLAG(Cstdlib)) {
      if (GET_FLAG(CP)) {
        outv[outc++] = "-lstdc++";
        //outv[outc++] = "-lm";
      }

      // libgcc can call libc which can call libgcc
      outv[outc++] = "-Wl,--start-group,--as-needed";
      outv[outc++] = "-lgcc";
      if (GET_FLAG(Clibccso)) outv[outc++] = "-lgcc_s";
      else outv[outc++] = "-lgcc_eh";
      outv[outc++] = "-lc";
      outv[outc++] = "-Wl,--no-as-needed,--end-group";
    }
    if (GET_FLAG(CPctordtor)) {
      outv[outc++] = find_TSpath("%s/cc/lib/crtend%s", topdir,
                                 GET_FLAG(Cshared), GET_FLAG(Cstatic));
      outv[outc++] = xmprintf("%s/lib/crtn.o", topdir);
    }
#ifdef ELF2FLT
    if (!GET_FLAG(Cmelf)) outv[outc++] = "-Wl,-elf2flt";
#endif
  }
  outv[outc] = 0;

  if (getenv("CCWRAP_DEBUG")) {
    fprintf(stderr, "%d/64 extra outv slots used\n", outc-keepc);
    fprintf(stderr, "outgoing:");
    for(i=0; i<outc; i++) fprintf(stderr, " \"%s\"", outv[i]);
    fprintf(stderr, "\n");
  }

  execvp(*outv, outv);
  fprintf(stderr, "%s: %s\n", *outv, strerror(errno));
  exit(1);

  return 0;
}
