#include "tink_tcp_mbedtls.h"

#include <stdlib.h>
#include <string.h>

#include "mbedtls/ctr_drbg.h"
#include "mbedtls/entropy.h"
#include "mbedtls/error.h"
#include "mbedtls/pk.h"
#include "mbedtls/ssl.h"
#include "mbedtls/x509_crt.h"

struct tink_tls_config {
	mbedtls_entropy_context entropy;
	mbedtls_ctr_drbg_context drbg;
	mbedtls_ssl_config conf;
	mbedtls_x509_crt ca;
	mbedtls_x509_crt own_cert;
	mbedtls_pk_context own_key;
	int has_ca;
	int has_own;
	const char **alpn_list;
	int alpn_count;
};

struct tink_tls_ssl {
	mbedtls_ssl_context ssl;
};

static int ensure_seeded(tink_tls_config *cfg) {
	return mbedtls_ctr_drbg_seed(&cfg->drbg, mbedtls_entropy_func, &cfg->entropy,
		(const unsigned char *)"tink_tcp", 8);
}

void *tink_tls_config_create(int is_server) {
	tink_tls_config *cfg = (tink_tls_config *)calloc(1, sizeof(tink_tls_config));
	if (!cfg)
		return NULL;
	mbedtls_entropy_init(&cfg->entropy);
	mbedtls_ctr_drbg_init(&cfg->drbg);
	mbedtls_ssl_config_init(&cfg->conf);
	mbedtls_x509_crt_init(&cfg->ca);
	mbedtls_x509_crt_init(&cfg->own_cert);
	mbedtls_pk_init(&cfg->own_key);

	if (ensure_seeded(cfg) != 0) {
		tink_tls_config_free(cfg);
		return NULL;
	}

	int endpoint = is_server ? MBEDTLS_SSL_IS_SERVER : MBEDTLS_SSL_IS_CLIENT;
	if (mbedtls_ssl_config_defaults(&cfg->conf, endpoint, MBEDTLS_SSL_TRANSPORT_STREAM,
			MBEDTLS_SSL_PRESET_DEFAULT) != 0) {
		tink_tls_config_free(cfg);
		return NULL;
	}
	mbedtls_ssl_conf_rng(&cfg->conf, mbedtls_ctr_drbg_random, &cfg->drbg);
	return cfg;
}

void tink_tls_config_free(void *pcfg) {
	tink_tls_config *cfg = (tink_tls_config *)pcfg;
	if (!cfg)
		return;
	if (cfg->alpn_list) {
		for (int i = 0; i < cfg->alpn_count; i++)
			free((void *)cfg->alpn_list[i]);
		free(cfg->alpn_list);
	}
	mbedtls_pk_free(&cfg->own_key);
	mbedtls_x509_crt_free(&cfg->own_cert);
	mbedtls_x509_crt_free(&cfg->ca);
	mbedtls_ssl_config_free(&cfg->conf);
	mbedtls_ctr_drbg_free(&cfg->drbg);
	mbedtls_entropy_free(&cfg->entropy);
	free(cfg);
}

int tink_tls_config_set_authmode(void *pcfg, int mode) {
	tink_tls_config *cfg = (tink_tls_config *)pcfg;
	if (!cfg)
		return -1;
	mbedtls_ssl_conf_authmode(&cfg->conf, mode);
	return 0;
}

int tink_tls_config_set_ca_pem(void *pcfg, const char *pem, size_t len) {
	tink_tls_config *cfg = (tink_tls_config *)pcfg;
	if (!cfg || !pem)
		return -1;
	int r = mbedtls_x509_crt_parse(&cfg->ca, (const unsigned char *)pem, len + 1);
	if (r != 0)
		return r;
	cfg->has_ca = 1;
	mbedtls_ssl_conf_ca_chain(&cfg->conf, &cfg->ca, NULL);
	return 0;
}

int tink_tls_config_set_own_cert_pem(void *pcfg, const char *cert_pem, size_t cert_len,
	const char *key_pem, size_t key_len) {
	tink_tls_config *cfg = (tink_tls_config *)pcfg;
	if (!cfg || !cert_pem || !key_pem)
		return -1;
	int r = mbedtls_x509_crt_parse(&cfg->own_cert, (const unsigned char *)cert_pem, cert_len + 1);
	if (r != 0)
		return r;
#if MBEDTLS_VERSION_MAJOR >= 3
	r = mbedtls_pk_parse_key(&cfg->own_key, (const unsigned char *)key_pem, key_len + 1, NULL, 0,
		mbedtls_ctr_drbg_random, &cfg->drbg);
#else
	r = mbedtls_pk_parse_key(&cfg->own_key, (const unsigned char *)key_pem, key_len + 1, NULL, 0);
#endif
	if (r != 0)
		return r;
	r = mbedtls_ssl_conf_own_cert(&cfg->conf, &cfg->own_cert, &cfg->own_key);
	if (r != 0)
		return r;
	cfg->has_own = 1;
	return 0;
}

int tink_tls_config_set_alpn(void *pcfg, const char **protos, int count) {
	tink_tls_config *cfg = (tink_tls_config *)pcfg;
	if (!cfg)
		return -1;
#ifdef MBEDTLS_SSL_ALPN
	if (cfg->alpn_list) {
		for (int i = 0; i < cfg->alpn_count; i++)
			free((void *)cfg->alpn_list[i]);
		free(cfg->alpn_list);
		cfg->alpn_list = NULL;
		cfg->alpn_count = 0;
	}
	if (count <= 0)
		return 0;
	cfg->alpn_list = (const char **)calloc((size_t)count + 1, sizeof(char *));
	if (!cfg->alpn_list)
		return -1;
	for (int i = 0; i < count; i++) {
		size_t n = strlen(protos[i]);
		char *copy = (char *)malloc(n + 1);
		if (!copy)
			return -1;
		memcpy(copy, protos[i], n + 1);
		cfg->alpn_list[i] = copy;
	}
	cfg->alpn_count = count;
	return mbedtls_ssl_conf_alpn_protocols(&cfg->conf, cfg->alpn_list);
#else
	(void)protos;
	(void)count;
	return 0;
#endif
}

void *tink_tls_ssl_create(void *pcfg) {
	tink_tls_config *cfg = (tink_tls_config *)pcfg;
	if (!cfg)
		return NULL;
	tink_tls_ssl *ssl = (tink_tls_ssl *)calloc(1, sizeof(tink_tls_ssl));
	if (!ssl)
		return NULL;
	mbedtls_ssl_init(&ssl->ssl);
	if (mbedtls_ssl_setup(&ssl->ssl, &cfg->conf) != 0) {
		tink_tls_ssl_free(ssl);
		return NULL;
	}
	return ssl;
}

void tink_tls_ssl_free(void *pssl) {
	tink_tls_ssl *ssl = (tink_tls_ssl *)pssl;
	if (!ssl)
		return;
	mbedtls_ssl_free(&ssl->ssl);
	free(ssl);
}

int tink_tls_ssl_set_hostname(void *pssl, const char *hostname) {
	tink_tls_ssl *ssl = (tink_tls_ssl *)pssl;
	if (!ssl || !hostname)
		return -1;
	return mbedtls_ssl_set_hostname(&ssl->ssl, hostname);
}

void tink_tls_ssl_set_bio(void *pssl, void *bio_ctx, tink_tls_bio_send_t f_send,
	tink_tls_bio_recv_t f_recv) {
	tink_tls_ssl *ssl = (tink_tls_ssl *)pssl;
	if (!ssl)
		return;
	mbedtls_ssl_set_bio(&ssl->ssl, bio_ctx, f_send, f_recv, NULL);
}

int tink_tls_ssl_handshake(void *pssl) {
	tink_tls_ssl *ssl = (tink_tls_ssl *)pssl;
	if (!ssl)
		return -1;
	return mbedtls_ssl_handshake(&ssl->ssl);
}

int tink_tls_ssl_read(void *pssl, unsigned char *buf, size_t len) {
	tink_tls_ssl *ssl = (tink_tls_ssl *)pssl;
	if (!ssl)
		return -1;
	return mbedtls_ssl_read(&ssl->ssl, buf, len);
}

int tink_tls_ssl_write(void *pssl, const unsigned char *buf, size_t len) {
	tink_tls_ssl *ssl = (tink_tls_ssl *)pssl;
	if (!ssl)
		return -1;
	return mbedtls_ssl_write(&ssl->ssl, buf, len);
}

const char *tink_tls_strerror(int code) {
	static char buf[256];
	mbedtls_strerror(code, buf, sizeof(buf));
	return buf;
}

int tink_tls_want_read(void) {
	return MBEDTLS_ERR_SSL_WANT_READ;
}

int tink_tls_want_write(void) {
	return MBEDTLS_ERR_SSL_WANT_WRITE;
}

int tink_tls_peer_close_notify(void) {
	return MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY;
}
