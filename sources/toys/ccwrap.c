/* vi: set ts=4 :*/
/*
 * Copyright (C) 2000 Manuel Novoa III
 * Copyright (C) 2002-2003 Erik Andersen
 * Copyright (C) 2006-2010 Rob Landley <rob@landley.net>
 *
 * Wrapper to use make a C compiler relocatable.
 *
 * Licensed under GPLv2.
 */

// No, we don't need to check the return value from asprintf().

#undef _FORTIFY_SOURCE

#define _GNU_SOURCE
#include <alloca.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/wait.h>

static char *topdir, *devprefix;
static char nostdinc[] = "-nostdinc";
static char nostdlib[] = "-nostdlib";

// For C++
static char nostdinc_plus[] = "-nostdinc++";

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

// Find an executable in a colon-separated path

char *find_in_path(char *path, char *filename, int has_exe)
{
	char *cwd = getcwd(NULL, 0);

	if (index(filename, '/') && is_file(filename, has_exe))
		return realpath(filename, NULL);

	while (path) {
		char *str, *next = path ? index(path, ':') : NULL;
		int len = next ? next-path : strlen(path);

		// The +3 is a corner case: if strlen(filename) is 1, make sure we
		// have enough space to append ".." to make topdir.
		str = malloc(strlen(filename) + (len ? len : strlen(cwd)) + 3);
		if (!len) sprintf(str, "%s/%s", cwd, filename);
		else {
			char *str2 = str;

			strncpy(str, path, len);
			str2 = str+len;
			*(str2++) = '/';
			strcpy(str2, filename);
		}

		// If it's not a directory, return it.
		if (is_file(str, has_exe)) {
			char *s = realpath(str, NULL);
			free(str);
			free(cwd);
			return s;
		} else free(str);

		if (next) next++;
		path = next;
	}
	free(cwd);

	return NULL;
}

// Some compiler versions don't provide separate T and S versions of begin/end,
// so fall back to the base version if they're not there.

char *find_TSpath(char *base, int use_shared, int use_static_linking)
{
	int i;
	char *temp;

	asprintf(&temp, base, devprefix,
			use_shared ? "S.o" : use_static_linking ? "T.o" : ".o");

	if (!is_file(temp, 0)) {
		free(temp);
		asprintf(&temp, base, devprefix, ".o");
	}

	return temp;
}

int main(int argc, char **argv)
{
	int linking = 1, use_static_linking = 0, use_shared_libgcc, used_x = 0;
	int use_stdinc = 1, use_start = 1, use_stdlib = 1, use_shared = 0;
	int source_count = 0, verbose = 0;
	int i, argcnt, lplen;
	char **cc_argv, **libpath;
	char *dlstr;
	char *cc, *toolprefix;
	char *debug_wrapper=getenv("CCWRAP_DEBUG");

	// For C++

	char *cpp = NULL;
	int prefixlen, ctor_dtor = 1, use_nostdinc_plus = 0;

	// For profiling
	int profile = 0;

	if(debug_wrapper) {
		fprintf(stderr,"incoming: ");
		for(cc_argv=argv;*cc_argv;cc_argv++)
			fprintf(stderr,"%s ",*cc_argv);
		fprintf(stderr,"\n\n");
	}

	// Allocate space for new command line
	cc_argv = alloca(sizeof(char*) * (argc + 128));

	// What directory is the wrapper script in?
	if(!(topdir = find_in_path(getenv("PATH"), argv[0], 1))) {
		fprintf(stderr, "can't find %s in $PATH (did you export it?)\n", argv[0]);
		exit(1);
	} else {
		char *path = getenv("PATH"), *temp;

		if (!path) path = "";

		// Add that directory to the start of $PATH.  (Better safe than sorry.)
		*rindex(topdir,'/') = 0;
		asprintf(&temp,"PATH=%s:%s/../tools/bin:%s",topdir,topdir,path);
		putenv(temp);

		// The directory above the wrapper script should have include, cc,
		// and lib directories.  However, the script could have a symlink
		// pointing to its directory (ala /bin -> /usr/bin), so append ".."
		// instead of trucating the path.
		strcat(topdir,"/..");
	}

	// What's the name of the C compiler we're wrapping?  (It may have a
	// cross-prefix.)
	cc = getenv("CCWRAP_CC");
	if (!cc) cc = "rawcc";

	// Check end of name, since there could be a cross-prefix on the thing
	toolprefix = strrchr(argv[0], '/');
	if (!toolprefix) toolprefix = argv[0];
	else toolprefix++;

	prefixlen = strlen(toolprefix);
	if (prefixlen>=3 && !strcmp(toolprefix+prefixlen-3, "gcc")) prefixlen -= 3;
	else if (!strcmp(toolprefix+prefixlen-2, "cc")) prefixlen -= 2;
	else if (!strcmp(toolprefix+prefixlen-2, "ld")) {
		prefixlen -= 2;

		// TODO: put support for wrapping the linker here.
	} else if (!strcmp(toolprefix+prefixlen-3, "cpp")) {
		prefixlen -=3;
		linking = 0;

	// Wrapping the c++ compiler?
	} else if (!strcmp(toolprefix+prefixlen-2, "++")) {
		int len = strlen(cc);
		cpp = alloca(len+1);
		strcpy(cpp, cc);
		cpp[len-1]='+';
		cpp[len-2]='+';
		use_nostdinc_plus = 1;
	}

	devprefix = getenv("CCWRAP_TOPDIR");
	if (!devprefix) {
		char *temp, *temp2;
		asprintf(&temp, "%.*sCCWRAP_TOPDIR", prefixlen, toolprefix);
		temp2 = temp;
		while (*temp2) {
			if (*temp2 == '-') *temp2='_';
			temp2++;
		}
		devprefix = getenv(temp);
	}
	if (!devprefix) devprefix = topdir;

	// Do we have libgcc_s.so?

	asprintf(&dlstr, "%s/lib/libgcc_s.so", devprefix);
	use_shared_libgcc = is_file(dlstr, 0);
	free(dlstr);

	// Figure out where the dynamic linker is.
	dlstr = getenv("CCWRAP_DYNAMIC_LINKER");
	if (!dlstr) dlstr = "/lib/ld-uClibc.so.0";
	asprintf(&dlstr, "-Wl,--dynamic-linker,%s", dlstr);

	lplen = 0;
	libpath = alloca(sizeof(char*) * (argc));
	libpath[lplen] = 0;

	// Parse the incoming compiler arguments.

	for (i=1; i<argc; i++) {
		if (argv[i][0] == '-' && argv[i][1]) { /* option */
			switch (argv[i][1]) {
				case 'M':	    /* generate dependencies */
				{
					char *p = argv[i];

					// -M and -MM imply -E and thus no linking
					// Other -MX options _don't_, including -MMD.
					if (p[2] && (p[2]!='M' || p[3])) break;
				}
				// fall through

				case 'c':		/* compile or assemble */
				case 'S':		/* generate assembler code */
				case 'E':		/* preprocess only */
					linking = 0;
					break;

				case 'L': 		/* library path */
					libpath[lplen++] = argv[i];
					libpath[lplen] = 0;
					if (!argv[i][2]) {
						argv[i] = 0;
						libpath[lplen++] = argv[++i];
						libpath[lplen] = 0;
					}
					argv[i] = 0;
					break;

				case 'v':		/* verbose */
					if (argv[i][2] == 0) verbose = 1;
					printf("Invoked as %s\n", argv[0]);
					printf("Reference path: %s\n", topdir);
					break;

				case 'n':
					if (!strcmp(nostdinc,argv[i])) use_stdinc = 0;
					else if (!strcmp("-nostartfiles",argv[i])) {
						ctor_dtor = 0;
						use_start = 0;
					} else if (!strcmp("-nodefaultlibs",argv[i])) {
						use_stdlib = 0;
						argv[i] = 0;
					} else if (!strcmp(nostdlib,argv[i])) {
						ctor_dtor = 0;
						use_start = 0;
						use_stdlib = 0;
					} else if (!strcmp(nostdinc_plus,argv[i]))
						use_nostdinc_plus = 0;
					break;

				case 's':
					if (!strcmp(argv[i],"-static")) {
						use_static_linking = 1;
						use_shared_libgcc=0;
					}
					if (!strcmp(argv[i],"-static-libgcc"))
						use_shared_libgcc = 0;
					if (!strcmp(argv[i],"-shared-libgcc"))
						use_shared_libgcc = 1;
					if (!strcmp("-shared",argv[i])) {
						use_start = 0;
						use_shared = 1;
					}
					break;

				case 'W':		/* -static could be passed directly to ld */
					if (!strncmp("-Wl,",argv[i],4)) {
						char *temp = strstr(argv[i], ",-static");
						if (temp && (!temp[7] || temp[7]==',')) {
							use_static_linking = 1;
							use_shared_libgcc=0;
						}
						if (strstr(argv[i],"--dynamic-linker")) dlstr = 0;
					}
					break;

				case 'p':
					if (!strncmp("-print-",argv[i],7)) {
						char *temp, *temp2;
						int itemp, showall = 0;

						temp = argv[i]+7;
						if (!strncmp(temp, "prog-name=", 10)) {
							printf("%.*s%s\n", prefixlen, toolprefix, temp+10);
							exit(0);
						} else if (!strcmp(temp, "search-dirs")) {
							printf("install: %s/\n",devprefix);
							printf("programs: %s\n",getenv("PATH"));
							printf("libraries: ");
							temp2 = "";
							showall = 1;
						} else if (!strncmp(temp, "file-name=", 10))
							temp2 = temp+10;
						else if (!strcmp(temp, "libgcc-file-name"))
							temp2="libgcc.a";
						else break;

						// Find this entry in the library path.
						for(itemp=0;;itemp++) {
							if (itemp == lplen)
								asprintf(&temp, "%s/cc/lib/%s", devprefix,
									temp2);
							else if (itemp == lplen+1)
								asprintf(&temp, "%s/lib/%s", devprefix, temp2);

							// This is so "include" finds the cc internal
							// include dir.  The uClibc build needs this.
							else if (itemp == lplen+2)
								asprintf(&temp, "%s/cc/%s", devprefix, temp2);
							else if (itemp == lplen+3) {
								temp = temp2;
								break;
							} else asprintf(&temp, "%s/%s", libpath[itemp],
											temp2);

							if (debug_wrapper)
								fprintf(stderr, "try=%s\n", temp);

							if (showall) printf(":%s"+(itemp?0:1), temp);
							else if (!access(temp, F_OK)) break;
						}



						printf("%s\n"+(showall ? 2 : 0), temp);
						exit(0);

					// Profiling.
					} else if (!strcmp("-pg",argv[i])) profile = 1;
					break;

				case 'f':
					// profiling
					if (strcmp("-fprofile-arcs",argv[i]) == 0) profile = 1;
					break;

				case 'x':
					used_x++;
					break;

				// --longopts

				case '-':
					if (!strncmp(argv[i],"--print-",8)
						|| !strncmp(argv[i],"--static",8)
						|| !strncmp(argv[i],"--shared",8))
					{
						argv[i]++;
						i--;
						continue;
					} else if (!strcmp("--no-ctors", argv[i])) {
						ctor_dtor = 0;
						argv[i] = 0;
					}
					break;
			}
		// assume it is an existing source file
		} else ++source_count;
	}

	argcnt = 0;

	cc_argv[argcnt++] = cpp ? cpp : cc;

	if (cpp) cc_argv[argcnt++] = "-fno-use-cxa-atexit";

	if (linking && source_count) {
//#if defined HAS_ELF && ! defined HAS_MMU
//		cc_argv[argcnt++] = "-Wl,-elf2flt";
//#endif
		cc_argv[argcnt++] = nostdlib;
		if (use_static_linking) cc_argv[argcnt++] = "-static";
		else if (dlstr) cc_argv[argcnt++] = dlstr;
		for (i=0; i<lplen; i++)
			if (libpath[i]) cc_argv[argcnt++] = libpath[i];

		// just to be safe:
		asprintf(cc_argv+(argcnt++), "-Wl,-rpath-link,%s/lib", devprefix);

		asprintf(cc_argv+(argcnt++), "-L%s/lib", devprefix);
		asprintf(cc_argv+(argcnt++), "-L%s/cc/lib", devprefix);
	}
	if (use_stdinc && source_count) {
		cc_argv[argcnt++] = nostdinc;

		if (cpp) {
			if (use_nostdinc_plus) cc_argv[argcnt++] = "-nostdinc++";
			cc_argv[argcnt++] = "-isystem";
			asprintf(cc_argv+(argcnt++), "%s/c++/include", devprefix);
		}

		cc_argv[argcnt++] = "-isystem";
		asprintf(cc_argv+(argcnt++), "%s/include", devprefix);
		cc_argv[argcnt++] = "-isystem";
		asprintf(cc_argv+(argcnt++), "%s/cc/include", devprefix);
	}

	cc_argv[argcnt++] = "-U__nptl__";

	if (linking && source_count) {

		if (profile)
			asprintf(cc_argv+(argcnt++), "%s/lib/gcrt1.o", devprefix);

		if (ctor_dtor) {
			asprintf(cc_argv+(argcnt++), "%s/lib/crti.o", devprefix);
			cc_argv[argcnt++]=find_TSpath("%s/cc/lib/crtbegin%s",
				use_shared, use_static_linking);
		}
		if (use_start && !profile)
			asprintf(cc_argv+(argcnt++), "%s/lib/%scrt1.o", devprefix, use_shared ? "S" : "");

		// Add remaining unclaimed arguments.

		for (i=1; i<argc; i++) if (argv[i]) cc_argv[argcnt++] = argv[i];

		if (used_x) cc_argv[argcnt++] = "-xnone";

		// Add standard libraries

		if (use_stdlib) {
			if (cpp) {
				cc_argv[argcnt++] = "-lstdc++";
				cc_argv[argcnt++] = "-lm";
			}

			// libgcc can call libc which can call libgcc

			cc_argv[argcnt++] = "-Wl,--start-group,--as-needed";
			cc_argv[argcnt++] = "-lgcc";
			if (!use_static_linking && use_shared_libgcc)
				cc_argv[argcnt++] = "-lgcc_s";
			else cc_argv[argcnt++] = "-lgcc_eh";
			cc_argv[argcnt++] = "-lc";
			cc_argv[argcnt++] = "-Wl,--no-as-needed,--end-group";
		}
		if (ctor_dtor) {
			cc_argv[argcnt++] = find_TSpath("%s/cc/lib/crtend%s", use_shared, 0);
			asprintf(cc_argv+(argcnt++), "%s/lib/crtn.o", devprefix);
		}
	} else for (i=1; i<argc; i++) if (argv[i]) cc_argv[argcnt++] = argv[i];

	cc_argv[argcnt++] = NULL;

	if (verbose) {
		for (i=0; cc_argv[i]; i++) printf("arg[%2i] = %s\n", i, cc_argv[i]);
		fflush(stdout);
	}

	if (debug_wrapper) {
		fprintf(stderr, "outgoing: ");
		for (i=0; cc_argv[i]; i++) fprintf(stderr, "%s ",cc_argv[i]);
		fprintf(stderr, "\n\n");
	}

	execvp(cc_argv[0], cc_argv);
	fprintf(stderr, "%s: %s\n", cpp ? cpp : cc, strerror(errno));
	exit(EXIT_FAILURE);
}
