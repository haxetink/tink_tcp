#if cpp
package tink.tcp.internal.cpp.mbedtls;

import cpp.*;

/** Opaque pointer to tink_tls_config / tink_tls_ssl */
typedef TlsConfigPtr = Star<cpp.Void>;
typedef TlsSslPtr = Star<cpp.Void>;

/**
  Thin bindings to owned mbedtls via native/cpp/tink_tcp_mbedtls.cpp (hxcpp-vendored mbedtls).
**/
@:headerInclude('tink_tcp_mbedtls.h')
@:build(tink.tcp.internal.cpp.Build.includeNative())
class NativeTls {
  public static function configCreate(isServer:Int):TlsConfigPtr
    return untyped __cpp__('tink_tls_config_create({0})', isServer);

  public static function configFree(cfg:TlsConfigPtr):Void
    untyped __cpp__('tink_tls_config_free({0})', cfg);

  public static function configSetAuthmode(cfg:TlsConfigPtr, mode:Int):Int
    return untyped __cpp__('tink_tls_config_set_authmode({0}, {1})', cfg, mode);

  public static function configSetCaPem(cfg:TlsConfigPtr, pem:String, len:Int):Int
    return untyped __cpp__('tink_tls_config_set_ca_pem({0}, {1}.utf8_str(), (size_t){2})', cfg, pem, len);

  public static function configSetOwnCertPem(cfg:TlsConfigPtr, certPem:String, certLen:Int, keyPem:String, keyLen:Int):Int
    return untyped __cpp__(
      'tink_tls_config_set_own_cert_pem({0}, {1}.utf8_str(), (size_t){2}, {3}.utf8_str(), (size_t){4})',
      cfg, certPem, certLen, keyPem, keyLen);

  public static function sslCreate(cfg:TlsConfigPtr):TlsSslPtr
    return untyped __cpp__('tink_tls_ssl_create({0})', cfg);

  public static function sslFree(ssl:TlsSslPtr):Void
    untyped __cpp__('tink_tls_ssl_free({0})', ssl);

  public static function sslSetHostname(ssl:TlsSslPtr, hostname:String):Int
    return untyped __cpp__('tink_tls_ssl_set_hostname({0}, {1}.utf8_str())', ssl, hostname);

  public static function sslSetBio(ssl:TlsSslPtr, bioCtx:Star<cpp.Void>,
      fSend:Callable<(Star<cpp.Void>, ConstStar<UInt8>, SizeT) -> Int>,
      fRecv:Callable<(Star<cpp.Void>, Star<UInt8>, SizeT) -> Int>):Void
    untyped __cpp__('tink_tls_ssl_set_bio({0}, {1}, {2}, {3})', ssl, bioCtx, fSend, fRecv);

  public static function sslHandshake(ssl:TlsSslPtr):Int
    return untyped __cpp__('tink_tls_ssl_handshake({0})', ssl);

  public static function sslRead(ssl:TlsSslPtr, buf:Star<UInt8>, len:Int):Int
    return untyped __cpp__('tink_tls_ssl_read({0}, {1}, (size_t){2})', ssl, buf, len);

  public static function sslWrite(ssl:TlsSslPtr, buf:ConstStar<UInt8>, len:Int):Int
    return untyped __cpp__('tink_tls_ssl_write({0}, {1}, (size_t){2})', ssl, buf, len);

  public static function strerror(code:Int):String
    return untyped __cpp__('::String(tink_tls_strerror({0}))', code);

  public static function wantRead():Int
    return untyped __cpp__('tink_tls_want_read()');

  public static function wantWrite():Int
    return untyped __cpp__('tink_tls_want_write()');

  public static function peerCloseNotify():Int
    return untyped __cpp__('tink_tls_peer_close_notify()');
}
#end
