#include <uv.h>
#include <stdlib.h>
#include <string.h>

/* Define before hl.h so DEFINE_PRIM uses our prefix. */
#ifdef HL_NAME
#	undef HL_NAME
#endif
#define HL_NAME(n) tink_tcp_##n
#include <hl.h>

typedef struct {
	vclosure *cb;
} shutdown_data;

static void on_shutdown(uv_shutdown_t *req, int status) {
	shutdown_data *d = (shutdown_data *)req->data;
	if (d) {
		if (d->cb) {
			hl_dyn_call(d->cb, NULL, 0);
			hl_remove_root(&d->cb);
		}
		free(d);
	}
	free(req);
}

HL_PRIM bool HL_NAME(stream_shutdown)(uv_stream_t *s, vclosure *c) {
	uv_shutdown_t *req;
	shutdown_data *d;
	if (!s)
		return false;
	req = (uv_shutdown_t *)malloc(sizeof(uv_shutdown_t));
	d = (shutdown_data *)malloc(sizeof(shutdown_data));
	d->cb = c;
	if (c)
		hl_add_root(&d->cb);
	req->data = d;
	if (uv_shutdown(req, s, on_shutdown) < 0) {
		if (c)
			hl_remove_root(&d->cb);
		free(d);
		free(req);
		return false;
	}
	return true;
}

DEFINE_PRIM(_BOOL, stream_shutdown, _ABSTRACT(uv_handle) _FUN(_VOID, _NO_ARG));
