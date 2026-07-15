#ifndef TINK_TCP_MBEDTLS_H
#define TINK_TCP_MBEDTLS_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int (*tink_tls_bio_send_t)(void *ctx, const unsigned char *buf, size_t len);
typedef int (*tink_tls_bio_recv_t)(void *ctx, unsigned char *buf, size_t len);

void *tink_tls_config_create(int is_server);
void tink_tls_config_free(void *cfg);
int tink_tls_config_set_authmode(void *cfg, int mode);
int tink_tls_config_set_ca_pem(void *cfg, const char *pem, size_t len);
int tink_tls_config_set_own_cert_pem(void *cfg, const char *cert_pem, size_t cert_len, const char *key_pem, size_t key_len);
int tink_tls_config_set_alpn(void *cfg, const char **protos, int count);

void *tink_tls_ssl_create(void *cfg);
void tink_tls_ssl_free(void *ssl);
int tink_tls_ssl_set_hostname(void *ssl, const char *hostname);
void tink_tls_ssl_set_bio(void *ssl, void *bio_ctx, tink_tls_bio_send_t f_send, tink_tls_bio_recv_t f_recv);
int tink_tls_ssl_handshake(void *ssl);
int tink_tls_ssl_read(void *ssl, unsigned char *buf, size_t len);
int tink_tls_ssl_write(void *ssl, const unsigned char *buf, size_t len);

const char *tink_tls_strerror(int code);
int tink_tls_want_read(void);
int tink_tls_want_write(void);
int tink_tls_peer_close_notify(void);

#ifdef __cplusplus
}
#endif

#endif
