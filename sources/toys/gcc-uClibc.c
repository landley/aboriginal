/* vi: set ts=4 :*/

#define TARGET_DIR "gcc/armv4l-unknown-linux/gnu/4.1.1"

/*
 * Copyright (C) 2000 Manuel Novoa III
 * Copyright (C) 2002-2003 Erik Andersen
 *
 * Wrapper to use uClibc with gcc, and make gcc relocatable.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/wait.h>

static char *topdir;
const char *mypath;
static char static_linking[] = "-static";
static char nostdinc[] = "-nostdinc";
static char nostartfiles[] = "-nostartfiles";
static char nodefaultlibs[] = "-nodefaultlibs";
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
		return strdup(filename);

	for (;;) {
		char *str, *next = path ? index(path, ':') : NULL;
		int len = next ? next-path : strlen(path);
		struct string_list *rnext;
		struct stat st;

		str = malloc(strlen(filename) + (len ? len : strlen(cwd)) + 2);
		if (!len) sprintf(str, "%s/%s", cwd, filename);
		else {
			strncpy(str, path, len);
			str += len;
			*(str++) = '/';
			strcpy(str, filename);
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

void xstrcat(char **string, ...)
{
	const char *c;
	va_list p; 
	/* Don't bother to calculate how big exerything 
	 * will be, just be careful to not overflow...  */
	va_start(p, string);
	*string = malloc(BUFSIZ);
	**string = '\0';
	while(1) {
		if (!(c = va_arg(p, const char *)))
			break;
		strcat(*string, c); 
	}
	va_end(p);
}

int main(int argc, char **argv)
{
	int use_build_dir = 0, linking = 1, use_static_linking = 0;
	int use_stdinc = 1, use_start = 1, use_stdlib = 1, use_pic = 0;
	int source_count = 0, use_rpath = 0, verbose = 0;
	int i, j, k, l, m, n, sawM = 0, sawdotoa = 0, sawcES = 0;
	char **gcc_argv, **gcc_argument, **libraries, **libpath;
	char *dlstr, *incstr, *devprefix, *libstr, *build_dlstr = 0;
	char *cc, *ep, *rpath_link[2], *rpath[2], *uClibc_inc[2], *our_lib_path[2];
	char *crt0_path[2], *crtbegin_path[2], *crtend_path[2];

	// For C++

	char *crti_path[2], *crtn_path[2], *cpp = NULL;
	int len, ctor_dtor = 1, cplusplus = 0, use_nostdinc_plus = 0;

	// For profiling
	int profile = 0;
	char *gcrt1_path[2];

	// What directory is the wrapper script in?
	if(!(mypath = find_in_path(getenv("PATH"), argv[0], 1))) {
		fprintf(stderr, "can't find %s in $PATH\n", argv[0]);
		exit(1);
	// Add that directory to the start of $PATH.  (Better safe than sorry.)
	} else {
		char *path = getenv("PATH"), *temp;

		*rindex(mypath,'/') = 0;
		temp = malloc(strlen(mypath)+strlen(path)+7);
		sprintf(temp,"PATH=%s:%s",mypath,path);
		putenv(temp);
	}

	// What's the name of the C compiler we're wrapping?  (It may have a
	// cross-prefix.)
	cc = getenv("UCLIBC_CC");
	if (!cc) cc = GCC_BIN;

	topdir = find_in_path("../"TARGET_DIR"/lib:../lib", "ld-uClibc.so.0", 0);
	if (!topdir) {
		fprintf(stderr, "unable to find ld-uClibc.so.0 near '%s'\n", mypath);
		exit(1);
	}
	*rindex(topdir,'/') = 0;

	// Check end of name, since there could be a cross-prefix on the thing
	len = strlen(argv[0]);
	if (!strcmp(argv[0]+len-3, "g++") || !strcmp(argv[0]+len-3, "c++")) {
		len = strlen(cc);
		if (strcmp(cc+len-3, "gcc")==0) {
			cpp = strdup(cc);
			cpp[len-1]='+';
			cpp[len-2]='+';
		}
		cplusplus = 1;
		use_nostdinc_plus = 1;
	}

	devprefix = getenv("UCLIBC_DEVEL_PREFIX");
	if (!devprefix) {
		devprefix = topdir;
	}

	incstr = getenv("UCLIBC_GCC_INC");
	libstr = getenv("UCLIBC_GCC_LIB");

	ep     = getenv("UCLIBC_ENV");
	if (!ep) {
		ep = "";
	}

	if (strstr(ep,"build") != 0) {
		use_build_dir = 1;
	}

	if (strstr(ep,"rpath") != 0) {
		use_rpath = 1;
	}


	xstrcat(&(rpath_link[0]), "-Wl,-rpath-link,", devprefix, "/lib", NULL);

	xstrcat(&(rpath[0]), "-Wl,-rpath,", devprefix, "/lib", NULL);

	xstrcat(&(uClibc_inc[0]), devprefix, "/include/", NULL);

//#ifdef CTOR_DTOR
	xstrcat(&(crt0_path[0]), devprefix, "/lib/crt1.o", NULL);
	xstrcat(&(crti_path[0]), devprefix, "/lib/crti.o", NULL);
	xstrcat(&(crtn_path[0]), devprefix, "/lib/crtn.o", NULL);
//#else
//	xstrcat(&(crt0_path[0]), devprefix, "/lib/crt0.o", NULL);
//#endif

	// profiling
	xstrcat(&(gcrt1_path[0]), devprefix, "/lib/gcrt1.o", NULL);

	xstrcat(&(our_lib_path[0]), "-L", devprefix, "/lib", NULL);

	// Figure out where the dynamic linker is.
	dlstr = getenv("UCLIBC_GCC_DLOPT");
	if (!dlstr) {
		dlstr = "-Wl,--dynamic-linker," DYNAMIC_LINKER;
	}

	m = 0;
	libraries = __builtin_alloca(sizeof(char*) * (argc));
	libraries[m] = '\0';

	n = 0;
	libpath = __builtin_alloca(sizeof(char*) * (argc));
	libpath[n] = '\0';

	for ( i = 1 ; i < argc ; i++ ) {
		if (argv[i][0] == '-' && argv[i][1]) { /* option */
			switch (argv[i][1]) {
				case 'c':		/* compile or assemble */
				case 'S':		/* generate assembler code */
				case 'E':		/* preprocess only */
				case 'M':	    /* generate dependencies */
					linking = 0;
					if (argv[i][1] == 'M')
						  sawM = 1;
					else
						  sawcES = 1;
					break;
				case 'L': 		/* library */
					libpath[n++] = argv[i];
					libpath[n] = '\0';
					if (argv[i][2] == 0) {
						argv[i] = '\0';
						libpath[n++] = argv[++i];
						libpath[n] = '\0';
					}
					argv[i] = '\0';
					break;
				case 'l': 		/* library */
					libraries[m++] = argv[i];
					libraries[m] = '\0';
					argv[i] = '\0';
					break;
				case 'v':		/* verbose */
					if (argv[i][2] == 0) verbose = 1;
					printf("Invoked as %s\n", argv[0]);
					printf("Reference path: %s\n", mypath);
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

				// Profiling.

				case 'p':
					if (strcmp("-pg",argv[i]) == 0) {
						profile = 1;
					}
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

				case '-':
					if (strstr(argv[i]+1,static_linking) != NULL) {
						use_static_linking = 1;
						argv[i]='\0';
					} else if (strcmp("--version",argv[i]) == 0) {
						printf("uClibc ");
						fflush(stdout);
						break;
					} else if (strcmp("--uclibc-use-build-dir",argv[i]) == 0) {
						use_build_dir = 1;
						argv[i]='\0';
					} else if (strcmp("--uclibc-use-rpath",argv[i]) == 0) {
						use_rpath = 1;
						argv[i]='\0';
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
			if (p > argv[i] && sawM && (strcmp (p, ".o") == 0 || strcmp (p, ".a") == 0))
				  sawdotoa = 1;
			++source_count;
		}
	}

	if (sawdotoa && sawM && !sawcES)
		  linking = 1;

	gcc_argv = __builtin_alloca(sizeof(char*) * (argc + 128));
	gcc_argument = __builtin_alloca(sizeof(char*) * (argc + 20));

	i = 0; k = 0;
	if (ctor_dtor) {
		xstrcat(&(crtbegin_path[0]), devprefix, "/lib/crtbegin.o", NULL);
		xstrcat(&(crtbegin_path[1]), devprefix, "/lib/crtbeginS.o", NULL);
		xstrcat(&(crtend_path[0]), devprefix, "/lib/crtend.o", NULL);
		xstrcat(&(crtend_path[1]), devprefix, "/lib/crtendS.o", NULL);
	}

	gcc_argv[i++] = cpp ? cpp : cc;

	if (EXTRAGCCFLAGS) gcc_argv[i++] = EXTRAGCCFLAGS;

	for ( j = 1 ; j < argc ; j++ ) {
		if (argv[j]=='\0') {
			continue;
		} else {
			gcc_argument[k++] = argv[j];
			gcc_argument[k] = '\0';
		}
	}

	if (cplusplus)
		gcc_argv[i++] = "-fno-use-cxa-atexit";

	if (linking && source_count) {
//#if defined HAS_ELF && ! defined HAS_MMU
//		gcc_argv[i++] = "-Wl,-elf2flt";
//#endif
		gcc_argv[i++] = nostdlib;
		if (use_static_linking) {
			gcc_argv[i++] = static_linking;
		}
		if (!use_static_linking) {
			if (dlstr && use_build_dir) {
				gcc_argv[i++] = build_dlstr;
			} else if (dlstr) {
				gcc_argv[i++] = dlstr;
			}
			if (use_rpath) {
				gcc_argv[i++] = rpath[use_build_dir];
			}
		}
		for ( l = 0 ; l < n ; l++ ) {
			if (libpath[l]) gcc_argv[i++] = libpath[l];
		}
		gcc_argv[i++] = rpath_link[use_build_dir]; /* just to be safe */
		if( libstr )
			gcc_argv[i++] = libstr;
		gcc_argv[i++] = our_lib_path[use_build_dir];
		if (!use_build_dir) {
			xstrcat(&(gcc_argv[i++]), "-L", devprefix, "/lib", NULL);
		}
	}
	if (use_stdinc && source_count) {
		gcc_argv[i++] = nostdinc;

		if (cplusplus) {
			char *cppinc;
			if (use_nostdinc_plus) {
				gcc_argv[i++] = nostdinc_plus;
			}
			xstrcat(&cppinc, uClibc_inc[use_build_dir], "c++/4.1.1", NULL);
			gcc_argv[i++] = "-isystem";
			gcc_argv[i++] = cppinc;
			xstrcat(&cppinc, uClibc_inc[use_build_dir], "c++/4.1.1/" TARGET_DIR, NULL);
			gcc_argv[i++] = "-isystem";
			gcc_argv[i++] = cppinc;
			xstrcat(&cppinc, uClibc_inc[use_build_dir], "c++/4.1.1", NULL);
			gcc_argv[i++] = "-isystem";
			gcc_argv[i++] = cppinc;
		}

		gcc_argv[i++] = "-isystem";
		gcc_argv[i++] = uClibc_inc[use_build_dir];
		gcc_argv[i++] = "-iwithprefix";
		gcc_argv[i++] = "include";
		if( incstr )
			gcc_argv[i++] = incstr;
	}

    gcc_argv[i++] = "-U__nptl__";

	if (linking && source_count) {

		if (profile) {
			gcc_argv[i++] = gcrt1_path[use_build_dir];
		}
		if (ctor_dtor) {
			gcc_argv[i++] = crti_path[use_build_dir];
			if (use_pic) {
				gcc_argv[i++] = crtbegin_path[1];
			} else {
				gcc_argv[i++] = crtbegin_path[0];
			}
		}
		if (use_start) {
			if (!profile) {
				gcc_argv[i++] = crt0_path[use_build_dir];
			}
		}
		for ( l = 0 ; l < k ; l++ ) {
			if (gcc_argument[l]) gcc_argv[i++] = gcc_argument[l];
		}
		if (use_stdlib) {
			//gcc_argv[i++] = "-Wl,--start-group";
			gcc_argv[i++] = "-lgcc";
			gcc_argv[i++] = "-lgcc_eh";
		}
		for ( l = 0 ; l < m ; l++ ) {
			if (libraries[l]) gcc_argv[i++] = libraries[l];
		}
		if (use_stdlib) {
			if (cplusplus) {
				gcc_argv[ i++ ] = "-lstdc++";
				gcc_argv[ i++ ] = "-lm";
			}
			gcc_argv[i++] = "-lc";
			gcc_argv[i++] = "-lgcc";
			gcc_argv[i++] = "-lgcc_eh";
			//gcc_argv[i++] = "-Wl,--end-group";
		}
		if (ctor_dtor) {
			if (use_pic) {
				gcc_argv[i++] = crtend_path[1];
			} else {
				gcc_argv[i++] = crtend_path[0];
			}

			gcc_argv[i++] = crtn_path[use_build_dir];
		}
	} else {
		for ( l = 0 ; l < k ; l++ ) {
			if (gcc_argument[l]) gcc_argv[i++] = gcc_argument[l];
		}
	}
	gcc_argv[i++] = NULL;

	if (verbose) {
		for ( j = 0 ; gcc_argv[j] ; j++ ) {
			printf("arg[%2i] = %s\n", j, gcc_argv[j]);
		}
		fflush(stdout);
	}

	//no need to free memory from xstrcat because we never return... 
	execvp(cpp ? cpp : cc, gcc_argv);
	fprintf(stderr, "%s: %s\n", cpp ? cpp : cc, strerror(errno));
	exit(EXIT_FAILURE);
}
