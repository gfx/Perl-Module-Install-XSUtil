#define PERL_NO_GET_CONTEXT
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#include "ppport.h"

#include "foo.h"
#include "foo/bar.h"
#include "foo/baz.h"

#include "mro_compat.h"

bool
foo_is_ok(void){
#ifdef FOO_OK
	return TRUE;
#else
	return FALSE;
#endif
}

MODULE = Foo	PACKAGE = Foo

PROTOTYPES: DISABLE

bool
foo_is_ok()

int
bar_is_ok(int a, int b, int c)
