#if cpp
package tink.tcp.internal.cpp.mbedtls;

class Mbedtls {
  /** MBEDTLS_SSL_VERIFY_NONE */
  public static inline var VERIFY_NONE = 0;
  /** MBEDTLS_SSL_VERIFY_OPTIONAL */
  public static inline var VERIFY_OPTIONAL = 1;
  /** MBEDTLS_SSL_VERIFY_REQUIRED */
  public static inline var VERIFY_REQUIRED = 2;

  public static function errorString(code:Int):String {
    return NativeTls.strerror(code);
  }
}
#end
