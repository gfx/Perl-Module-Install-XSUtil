/* foo/bar.h for testing */

#define DUMMY
#define X(name) int name

int bar_is_ok(
	X(a), X(b), X(c)
) DUMMY;

