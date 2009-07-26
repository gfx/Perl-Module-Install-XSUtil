#define PERL_NO_GET_CONTEXT
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#include "ppport.h"

#include "foo.h"
#include "foo/bar.h"
#include "foo/baz.h"

int bar_is_ok(
	X(a), X(b), X(c)
){
	return a + b + c;
}

