/* vi: set ts=4 :*/
/*
 * Copyright (C) 2000 Manuel Novoa III
 * Copyright (C) 2002-2003 Erik Andersen
 * Copyright (C) 2006 Rob Landley <rob@landley.net>
 *
 * Wrapper to use uClibc with gcc, and make gcc relocatable.
 */

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
static char static_linking[] = "-static";
static char nostdinc[] = "-nostdinc";
static char nostartfiles[] = "-nostartfiles";
static char nodefaultlibs[] = "-nodefaultlibs";
static char nostdlib[] = "-nostdlib";

// For C++
static char nostdinc_plus[] = "-nostdinc++";

// #define GIMME_AN_S for wrapper to support --enable-shared toolchain.

#ifdef GIMME_AN_S
#define ADD_GCC_S() \
	do { \
		if (!use_static_linking) \
			gcc_argv[argcnt++] = "-Wl,--as-needed,-lgcc_s,--no-as-needed"; \
		else gcc_argv[argcnt++] = "-lgcc_eh"; \
	} while (0);
#else
#define ADD_GCC_S()
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
	char *cwd = getcwd(NULL, 0);

	if (index(filename, '/') && is_file(filename, has_exe))
		return strdup(filename);

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
		if (is_file(str, has_exe)) return str;
		else free(str);

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
	int use_stdinc = 1, use_start = 1, use_stdlib = 1, use_pic = 0;
	int source_count = 0, verbose = 0;
	int i, argcnt, liblen, lplen, sawM = 0, sawdotoa = 0, sawcES = 0;
	char **gcc_argv, **libraries, **libpath;
	char *dlstr, *incstr, *devprefix, *libstr;
	char *cc, *rpath_link, *rpath, *uClibc_inc, *our_lib_path[2];
	char *crt0_path, *crtbegin_path[2], *crtend_path[2];
	char *debug_wrapper=getenv("DEBUG_WRAPPER");

	// For C++

	char *crti_path, *crtn_path, *cpp = NULL;
	int len, ctor_dtor = 1, cplusplus = 0, use_nostdinc_plus = 0;

	// For profiling
	int profile = 0;
	char *gcrt1_path;

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
		fprintf(stderr, "can't find %s in $PATH\n", argv[0]);
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
	cc = getenv("UCLIBC_CC");
	if (!cc) cc = GCC_UNWRAPPED_NAME;

	
	// Check end of name, since there could be a cross-prefix on the thing
	len = strlen(argv[0]);
	if (!strcmp(argv[0]+len-2, "ld")) {

		// TODO: put support for wrapping the linker here.

	// Wrapping the c++ compiler?
	} else if (!strcmp(argv[0]+len-2, "++")) {
		len = strlen(cc);
		cpp = alloca(len+1);
		strcpy(cpp, cc);
		cpp[len-1]='+';
		cpp[len-2]='+';
		cplusplus = 1;
		use_nostdinc_plus = 1;
	}

	devprefix = getenv("UCLIBC_DEVEL_PREFIX");
	if (!devprefix) {
		devprefix = topdir;
	}

	incstr = getenv("UCLIBC_GCC_INC");
	libstr = getenv("UCLIBC_GCC_LIB");

	asprintf(&rpath_link,"-Wl,-rpath-link,%s/lib", devprefix);
	asprintf(&rpath, "-Wl,-rpath,%s/lib", devprefix);
	asprintf(&uClibc_inc, "%s/include/", devprefix);

	asprintf(&crt0_path, "%s/lib/crt1.o", devprefix);
	asprintf(&crti_path, "%s/lib/crti.o", devprefix);
	asprintf(&crtn_path, "%s/lib/crtn.o", devprefix);

	// profiling
	asprintf(&gcrt1_path, "%s/lib/gcrt1.o", devprefix);
	asprintf(our_lib_path, "-L%s/lib", devprefix);

	// Figure out where the dynamic linker is.
	dlstr = getenv("UCLIBC_DYNAMIC_LINKER");
	if (!dlstr) dlstr = "/lib/ld-uClibc.so.0";
	asprintf(&dlstr, "-Wl,--dynamic-linker,%s", dlstr);

	liblen = 0;
	libraries = alloca(sizeof(char*) * (argc));
	libraries[liblen] = '\0';

	lplen = 0;
	libpath = alloca(sizeof(char*) * (argc));
	libpath[lplen] = '\0';

	// Parse the incoming gcc arguments.

	for ( i = 1 ; i < argc ; i++ ) {
		if (argv[i][0] == '-' && argv[i][1]) { /* option */
			switch (argv[i][1]) {
				case 'c':		/* compile or assemble */
				case 'S':		/* generate assembler code */
				case 'E':		/* preprocess only */
				case 'M':	    /* generate dependencies */
					linking = 0;
					if (argv[i][1] == 'M') sawM = 1;
					else sawcES = 1;
					break;

				case 'L': 		/* library path */
					libpath[lplen++] = argv[i];
					libpath[lplen] = '\0';
					if (argv[i][2] == 0) {
						argv[i] = '\0';
						libpath[lplen++] = argv[++i];
						libpath[lplen] = '\0';
					}
					argv[i] = '\0';
					break;

				case 'l': 		/* library */
					libraries[liblen++] = argv[i];
					libraries[liblen] = '\0';
					argv[i] = '\0';
					break;

				case 'v':		/* verbose */
					if (argv[i][2] == 0) verbose = 1;
					printf("Invoked as %s\n", argv[0]);
					printf("Reference path: %s\n", topdir);
					break;

				case 'n':
					if (strcmp(nostdinc,argv[i]) == 0) {
						use_stdinc = 0;
					} else if (strcmp(nostartfiles,argv[i]) == 0) {
						ctor_dtor = 0;
						use_start = 0;
					} else if (strcmp(nodefaultlibs,argv[i]) == 0) {
						use_stdlib = 0;
						argv[i] = '\0';
					} else if (strcmp(nostdlib,argv[i]) == 0) {
						ctor_dtor = 0;
						use_start = 0;
						use_stdlib = 0;
					} else if (strcmp(nostdinc_plus,argv[i]) == 0) {
						if (cplusplus==1) {
							use_nostdinc_plus = 0;
						}
					}
					break;

				case 's':
					if (strstr(argv[i],static_linking) != NULL) {
						use_static_linking = 1;
					}
					if (strcmp("-shared",argv[i]) == 0) {
						use_start = 0;
						use_pic = 1;
					}
					break;

				case 'W':		/* -static could be passed directly to ld */
					if (strncmp("-Wl,",argv[i],4) == 0) {
						if (strstr(argv[i],static_linking) != 0) {
							use_static_linking = 1;
						}
						if (strstr(argv[i],"--dynamic-linker") != 0) {
							dlstr = 0;
						}
					}
					break;

                case 'p':
wow_this_sucks:
					if (!strncmp("-print-",argv[i],7)) {
						char *temp, *temp2;
						int itemp, showall = 0;

						temp = argv[i]+7;
						if (!strcmp(temp, "search-dirs")) {
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
							if (itemp == lplen) {
								asprintf(&temp, "%s/gcc/lib/%s", devprefix, temp2);
							} else if (itemp == lplen+1) {
								// This is so "include" finds the gcc internal
								// include dir.  The uClibc build needs this.
								asprintf(&temp, "%s/gcc/%s", devprefix, temp2);
							} else if (itemp == lplen+2) {
								temp = temp2;
								break;
							} else {
								asprintf(&temp, "%s/%s", libpath[itemp],
											temp2);
							}
							if (showall) printf(":%s"+(itemp?0:1), temp);
							else if (!access(temp, F_OK)) break;
						}

						printf("%s\n"+(showall ? 2 : 0), temp);
						exit(0);

					// Profiling.
					} else if (!strcmp("-pg",argv[i])) profile = 1;
					break;

				case 'f':
					/* Check if we are doing PIC */
					if (strcmp("-fPIC",argv[i]) == 0) {
						use_pic = 1;
					} else if (strcmp("-fpic",argv[i]) == 0) {
						use_pic = 1;
 
					// profiling
					} else if (strcmp("-fprofile-arcs",argv[i]) == 0) {
						profile = 1;
					}
					break;

				// --longopts

				case '-':
					if (!strncmp(argv[i],"--print-",8)) {
						argv[i]++;
						goto wow_this_sucks;
					} else if (strstr(argv[i]+1,static_linking) != NULL) {
						use_static_linking = 1;
						argv[i]='\0';
					} else if (!strcmp("--version",argv[i])) {
						printf("uClibc ");
						fflush(stdout);
						break;
					} else if (strcmp ("--uclibc-cc", argv[i]) == 0 && argv[i + 1]) {
						cc = argv[i + 1];
						argv[i] = 0;
						argv[i + 1] = 0;
					} else if (strncmp ("--uclibc-cc=", argv[i], 12) == 0) {
						cc = argv[i] + 12;
						argv[i] = 0;
					} else if (strcmp("--uclibc-no-ctors",argv[i]) == 0) {
						ctor_dtor = 0;
						argv[i]='\0';
					}
					break;
			}
		} else {				/* assume it is an existing source file */
			char *p = strchr (argv[i], '\0') - 2;
			if (p > argv[i] && sawM && (!strcmp(p, ".o") || !strcmp(p, ".a")))
				  sawdotoa = 1;
			++source_count;
		}
	}

	if (sawdotoa && sawM && !sawcES)
		linking = 1;

	argcnt = 0;
	if (ctor_dtor) {
		asprintf(crtbegin_path, "%s/gcc/lib/crtbegin.o", devprefix);
		asprintf(crtbegin_path+1, "%s/gcc/lib/crtbeginS.o", devprefix);
		asprintf(crtend_path, "%s/gcc/lib/crtend.o", devprefix);
		asprintf(crtend_path+1, "%s/gcc/lib/crtendS.o", devprefix);
	}

	gcc_argv[argcnt++] = cpp ? cpp : cc;

	if (cplusplus) gcc_argv[argcnt++] = "-fno-use-cxa-atexit";

	if (linking && source_count) {
//#if defined HAS_ELF && ! defined HAS_MMU
//		gcc_argv[argcnt++] = "-Wl,-elf2flt";
//#endif
		gcc_argv[argcnt++] = nostdlib;
		if (use_static_linking) {
			gcc_argv[argcnt++] = static_linking;
		} else {
			if (dlstr) {
				gcc_argv[argcnt++] = dlstr;
			}
		}
		for ( i = 0 ; i < lplen ; i++ )
			if (libpath[i]) gcc_argv[argcnt++] = libpath[i];
		gcc_argv[argcnt++] = rpath_link; /* just to be safe */
		if( libstr )
			gcc_argv[argcnt++] = libstr;
		gcc_argv[argcnt++] = our_lib_path[0];
		asprintf(gcc_argv+(argcnt++), "-L%s/gcc/lib", devprefix);
	}
	if (use_stdinc && source_count) {
		gcc_argv[argcnt++] = nostdinc;

		if (cplusplus) {
			if (use_nostdinc_plus) {
				gcc_argv[argcnt++] = nostdinc_plus;
			}
			gcc_argv[argcnt++] = "-isystem";
			asprintf(gcc_argv+(argcnt++), "%sc++/4.1.1", uClibc_inc);
			//char *cppinc;
			//#define TARGET_DIR "gcc/armv4l-unknown-linux/gnu/4.1.1"
			//xstrcat(&cppinc, uClibc_inc, "c++/4.1.1/" TARGET_DIR, NULL);
			//gcc_argv[argcnt++] = "-isystem";
			//gcc_argv[argcnt++] = cppinc;
			//xstrcat(&cppinc, uClibc_inc, "c++/4.1.1", NULL);
			//gcc_argv[argcnt++] = "-isystem";
			//gcc_argv[argcnt++] = cppinc;
		}

		gcc_argv[argcnt++] = "-isystem";
		gcc_argv[argcnt++] = uClibc_inc;
		gcc_argv[argcnt++] = "-isystem";
		asprintf(gcc_argv+(argcnt++), "%s/gcc/include", devprefix);
		if(incstr) gcc_argv[argcnt++] = incstr;
	}

    gcc_argv[argcnt++] = "-U__nptl__";

	if (linking && source_count) {

		if (profile) {
			gcc_argv[argcnt++] = gcrt1_path;
		}
		if (ctor_dtor) {
			gcc_argv[argcnt++] = crti_path;
			if (use_pic) {
				gcc_argv[argcnt++] = crtbegin_path[1];
			} else {
				gcc_argv[argcnt++] = crtbegin_path[0];
			}
		}
		if (use_start && !profile) gcc_argv[argcnt++] = crt0_path;

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
			if (cplusplus) {
				gcc_argv[argcnt++] = "-lstdc++";
				gcc_argv[argcnt++] = "-lm";
			}
			gcc_argv[argcnt++] = "-lc";
			gcc_argv[argcnt++] = "-lgcc";
			ADD_GCC_S();
			//gcc_argv[argcnt++] = "-Wl,--end-group";
		}
		if (ctor_dtor) {
			gcc_argv[argcnt++] = crtend_path[use_pic ? 1 : 0];
			gcc_argv[argcnt++] = crtn_path;
		}
	} else for (i=1; i<argc; i++) if (argv[i]) gcc_argv[argcnt++] = argv[i];

	gcc_argv[argcnt++] = NULL;

	if (verbose) {
		for ( i = 0 ; gcc_argv[i] ; i++ ) {
			printf("arg[%2i] = %s\n", i, gcc_argv[i]);
		}
		fflush(stdout);
	}

	if (debug_wrapper) {
		fprintf(stderr, "outgoing: ");
		for(i=0; gcc_argv[i]; i++) fprintf(stderr, "%s ",gcc_argv[i]);
		fprintf(stderr, "\n\n");
	}

	//no need to free memory from xstrcat because we never return.
	execvp(gcc_argv[0], gcc_argv);
	fprintf(stderr, "%s: %s\n", cpp ? cpp : cc, strerror(errno));
	exit(EXIT_FAILURE);
}
