/* vi: set ts=4 :*/
/*
 * Copyright (C) 2000 Manuel Novoa III
 * Copyright (C) 2002-2003 Erik Andersen
 * Copyright (C) 2006-2009 Rob Landley <rob@landley.net>
 *
 * Wrapper to use uClibc with gcc, and make gcc relocatable.
 *
 * Licensed under GPLv2.
 */

#ifndef GCC_UNWRAPPED_NAME
#error You forgot -DGCC_UNWRAPPED_NAME='"'$PREFIX-rawgcc'"'
#else

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

static char *topdir;
static char nostdinc[] = "-nostdinc";
static char nostartfiles[] = "-nostartfiles";
static char nodefaultlibs[] = "-nodefaultlibs";
static char nostdlib[] = "-nostdlib";

// For C++
static char nostdinc_plus[] = "-nostdinc++";

// gcc 4.3 generates tons of spurious warnings which you can't shut off.

#define xasprintf(...) do {int ignore=asprintf(__VA_ARGS__);} while(0)

// #define GIMME_AN_S for wrapper to support --enable-shared toolchain.

#ifdef GIMME_AN_S
#define ADD_GCC_S() \
	do { \
		if (!use_static_linking) \
			gcc_argv[argcnt++] = "-Wl,--as-needed,-lgcc_s,--no-as-needed"; \
		else gcc_argv[argcnt++] = "-lgcc_eh"; \
	} while (0);
#else
#define ADD_GCC_S() gcc_argv[argcnt++] = "-lgcc_eh"
#endif

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
	// Don't segfault if $PATH wasn't exported
	if (!path) return 0;

	char *cwd = getcwd(NULL, 0);

	if (index(filename, '/') && is_file(filename, has_exe))
		return realpath(filename, NULL);

	for (;;) {
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
			return s;
		} else free(str);

		if (!next) break;
		path += len;
		path++;
	}
	free(cwd);

	return NULL;
}

int main(int argc, char **argv)
{
	int linking = 1, use_static_linking = 0;
	int use_stdinc = 1, use_start = 1, use_stdlib = 1, use_shared = 0;
	int source_count = 0, verbose = 0;
	int i, argcnt, liblen, lplen;
	char **gcc_argv, **libraries, **libpath;
	char *dlstr, *devprefix;
	char *cc, *toolprefix;
	char *debug_wrapper=getenv("WRAPPER_DEBUG");

	// For C++

	char *cpp = NULL;
	int prefixlen, ctor_dtor = 1, use_nostdinc_plus = 0;

	// For profiling
	int profile = 0;

	if(debug_wrapper) {
		fprintf(stderr,"incoming: ");
		for(gcc_argv=argv;*gcc_argv;gcc_argv++)
			fprintf(stderr,"%s ",*gcc_argv);
		fprintf(stderr,"\n\n");
	}

	// Allocate space for new command line
	gcc_argv = alloca(sizeof(char*) * (argc + 128));

	// What directory is the wrapper script in?
	if(!(topdir = find_in_path(getenv("PATH"), argv[0], 1))) {
		fprintf(stderr, "can't find %s in $PATH (did you export it?)\n", argv[0]);
		exit(1);
	} else {
		char *path = getenv("PATH"), *temp;

		// Add that directory to the start of $PATH.  (Better safe than sorry.)
		*rindex(topdir,'/') = 0;
		temp = malloc(5+strlen(topdir)+1+strlen(topdir)+14+strlen(path)+1);
		sprintf(temp,"PATH=%s:%s/../tools/bin:%s",topdir,topdir,path);
		putenv(temp);

		// The directory above the wrapper script should have include, gcc,
		// and lib directories.  However, the script could have a symlink
		// pointing to its directory (ala /bin -> /usr/bin), so append ".."
		// instead of trucating the path.
		strcat(topdir,"/..");
	}

	// What's the name of the C compiler we're wrapping?  (It may have a
	// cross-prefix.)
	cc = getenv("WRAPPER_CC");
	if (!cc) cc = GCC_UNWRAPPED_NAME;

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

	// Wrapping the c++ compiler?
	} else if (!strcmp(toolprefix+prefixlen-2, "++")) {
		int len = strlen(cc);
		cpp = alloca(len+1);
		strcpy(cpp, cc);
		cpp[len-1]='+';
		cpp[len-2]='+';
		use_nostdinc_plus = 1;
	}

	devprefix = getenv("WRAPPER_TOPDIR");
	if (!devprefix) {
		char *temp, *temp2;
		xasprintf(&temp, "%.*sWRAPPER_TOPDIR", prefixlen, toolprefix);
		temp2 = temp;
		while (*temp2) {
			if (*temp2 == '-') *temp2='_';
			temp2++;
		}
		devprefix = getenv(temp);
	}
	if (!devprefix) devprefix = topdir;


	// Figure out where the dynamic linker is.
	dlstr = getenv("UCLIBC_DYNAMIC_LINKER");
	if (!dlstr) dlstr = "/lib/ld-uClibc.so.0";
	xasprintf(&dlstr, "-Wl,--dynamic-linker,%s", dlstr);

	liblen = 0;
	libraries = alloca(sizeof(char*) * (argc));
	libraries[liblen] = 0;

	lplen = 0;
	libpath = alloca(sizeof(char*) * (argc));
	libpath[lplen] = 0;

	// Parse the incoming gcc arguments.

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

				case 'l': 		/* library */
					libraries[liblen++] = argv[i];
					libraries[liblen] = 0;
					argv[i] = 0;
					break;

				case 'v':		/* verbose */
					if (argv[i][2] == 0) verbose = 1;
					printf("Invoked as %s\n", argv[0]);
					printf("Reference path: %s\n", topdir);
					break;

				case 'n':
					if (!strcmp(nostdinc,argv[i])) use_stdinc = 0;
					else if (!strcmp(nostartfiles,argv[i])) {
						ctor_dtor = 0;
						use_start = 0;
					} else if (!strcmp(nodefaultlibs,argv[i])) {
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
					if (!strcmp(argv[i],"-static")) use_static_linking = 1;
					if (!strcmp("-shared",argv[i])) {
						use_start = 0;
						use_shared = 1;
					}
					break;

				case 'W':		/* -static could be passed directly to ld */
					if (!strncmp("-Wl,",argv[i],4)) {
						char *temp = strstr(argv[i], ",-static");
						if (temp && (!temp[7] || temp[7]==','))
							use_static_linking = 1;
						if (strstr(argv[i],"--dynamic-linker")) dlstr = 0;
					}
					break;

                case 'p':
wow_this_sucks:
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
								xasprintf(&temp, "%s/cc/lib/%s", devprefix,
									temp2);
							else if (itemp == lplen+1)
								xasprintf(&temp, "%s/lib/%s", devprefix, temp2);

							// This is so "include" finds the cc internal
							// include dir.  The uClibc build needs this.
							else if (itemp == lplen+2)
								xasprintf(&temp, "%s/cc/%s", devprefix, temp2);
							else if (itemp == lplen+3) {
								temp = temp2;
								break;
							} else xasprintf(&temp, "%s/%s", libpath[itemp],
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

				// --longopts

				case '-':
					if (!strncmp(argv[i],"--print-",8)) {
						argv[i]++;
						goto wow_this_sucks;
					} else if (!strcmp(argv[i], "--static")) {
						use_static_linking = 1;
						argv[i] = 0;
					} else if (!strcmp("--version", argv[i])) {
						printf("uClibc ");
						fflush(stdout);
						break;
					} else if (!strcmp("--uclibc-cc", argv[i]) && argv[i+1]) {
						cc = argv[i + 1];
						argv[i] = 0;
						argv[i + 1] = 0;
					} else if (!strncmp ("--uclibc-cc=", argv[i], 12)) {
						cc = argv[i] + 12;
						argv[i] = 0;
					} else if (!strcmp("--uclibc-no-ctors", argv[i])) {
						ctor_dtor = 0;
						argv[i] = 0;
					}
					break;
			}
		// assume it is an existing source file
		} else ++source_count;
	}

	argcnt = 0;

	gcc_argv[argcnt++] = cpp ? cpp : cc;

	if (cpp) gcc_argv[argcnt++] = "-fno-use-cxa-atexit";

	if (linking && source_count) {
//#if defined HAS_ELF && ! defined HAS_MMU
//		gcc_argv[argcnt++] = "-Wl,-elf2flt";
//#endif
		gcc_argv[argcnt++] = nostdlib;
		if (use_static_linking) gcc_argv[argcnt++] = "-static";
		else if (dlstr) gcc_argv[argcnt++] = dlstr;
		for (i=0; i<lplen; i++)
			if (libpath[i]) gcc_argv[argcnt++] = libpath[i];

		// just to be safe:
		xasprintf(gcc_argv+(argcnt++), "-Wl,-rpath-link,%s/lib", devprefix);


		xasprintf(gcc_argv+(argcnt++), "-L%s/lib", devprefix);
		xasprintf(gcc_argv+(argcnt++), "-L%s/cc/lib", devprefix);
	}
	if (use_stdinc && source_count) {
		gcc_argv[argcnt++] = nostdinc;

		if (cpp) {
			if (use_nostdinc_plus) gcc_argv[argcnt++] = nostdinc_plus;
			gcc_argv[argcnt++] = "-isystem";
			xasprintf(gcc_argv+(argcnt++), "%s/c++/include", devprefix);
		}

		gcc_argv[argcnt++] = "-isystem";
		xasprintf(gcc_argv+(argcnt++), "%s/include", devprefix);
		gcc_argv[argcnt++] = "-isystem";
		xasprintf(gcc_argv+(argcnt++), "%s/cc/include", devprefix);
	}

	gcc_argv[argcnt++] = "-U__nptl__";

	if (linking && source_count) {

		if (profile)
			xasprintf(gcc_argv+(argcnt++), "%s/lib/gcrt1.o", devprefix);

		if (ctor_dtor) {
			xasprintf(gcc_argv+(argcnt++), "%s/lib/crti.o", devprefix);
			xasprintf(gcc_argv+(argcnt++), "%s/cc/lib/crtbegin%s", devprefix,
					use_shared ? "S.o" : use_static_linking ? "T.o" : ".o");
		}
		if (use_start && !profile)
			xasprintf(gcc_argv+(argcnt++), "%s/lib/crt1.o", devprefix);

		// Add remaining unclaimed arguments.

		for (i=1; i<argc; i++) if (argv[i]) gcc_argv[argcnt++] = argv[i];

		if (use_stdlib) {
			//gcc_argv[argcnt++] = "-Wl,--start-group";
			gcc_argv[argcnt++] = "-lgcc";
			ADD_GCC_S();
		}
		for (i = 0 ; i < liblen ; i++)
			if (libraries[i]) gcc_argv[argcnt++] = libraries[i];
		if (use_stdlib) {
			if (cpp) {
				gcc_argv[argcnt++] = "-lstdc++";
				gcc_argv[argcnt++] = "-lm";
			}
			gcc_argv[argcnt++] = "-lc";
			gcc_argv[argcnt++] = "-lgcc";
			ADD_GCC_S();
			//gcc_argv[argcnt++] = "-Wl,--end-group";
		}
		if (ctor_dtor) {
			xasprintf(gcc_argv+(argcnt++), "%s/cc/lib/crtend%s", devprefix,
					use_shared ? "S.o" : ".o");
			xasprintf(gcc_argv+(argcnt++), "%s/lib/crtn.o", devprefix);
		}
	} else for (i=1; i<argc; i++) if (argv[i]) gcc_argv[argcnt++] = argv[i];

	gcc_argv[argcnt++] = NULL;

	if (verbose) {
		for (i=0; gcc_argv[i]; i++) printf("arg[%2i] = %s\n", i, gcc_argv[i]);
		fflush(stdout);
	}

	if (debug_wrapper) {
		fprintf(stderr, "outgoing: ");
		for (i=0; gcc_argv[i]; i++) fprintf(stderr, "%s ",gcc_argv[i]);
		fprintf(stderr, "\n\n");
	}

	execvp(gcc_argv[0], gcc_argv);
	fprintf(stderr, "%s: %s\n", cpp ? cpp : cc, strerror(errno));
	exit(EXIT_FAILURE);
}
#endif
