#if cpp
package tink.tcp.tls.cpp;

import cpp.*;
import tink.tcp.Tls.TlsServerOptions;
import tink.tcp.cpp.mbedtls.Mbedtls;
import tink.tcp.cpp.mbedtls.NativeTls;
import tink.tcp.cpp.mbedtls.NativeTls.TlsConfigPtr;

abstract CppTlsServerConfig(TlsServerOptions) from TlsServerOptions {
  public function createContext():CppTlsContext {
    final conf = NativeTls.configCreate(1);
    if (conf == null)
      throw new haxe.Exception('mbedtls config create failed');

    CppTlsPem.requirePkcs8(this.key);
    final certPem = CppTlsPem.asCString(this.cert);
    final keyPem = CppTlsPem.asCString(this.key);
    final own = NativeTls.configSetOwnCertPem(conf, certPem, certPem.length, keyPem, keyPem.length);
    if (own != 0) {
      NativeTls.configFree(conf);
      throw new haxe.Exception('Failed to set server cert: ${Mbedtls.errorString(own)}');
    }

    if (this.ca != null) {
      final caPem = CppTlsPem.asCString(this.ca);
      final r = NativeTls.configSetCaPem(conf, caPem, caPem.length);
      if (r != 0) {
        NativeTls.configFree(conf);
        throw new haxe.Exception('Failed to parse CA: ${Mbedtls.errorString(r)}');
      }
    }

    NativeTls.configSetAuthmode(conf, serverAuthmode());

    if (this.alpn != null && this.alpn.length > 0)
      throw new haxe.Exception('ALPN is not yet supported on the cpp target');

    return new CppTlsContext(conf);
  }

  function serverAuthmode():Int {
    if (this.requestCert == true)
      return this.rejectUnauthorized == true ? Mbedtls.VERIFY_REQUIRED : Mbedtls.VERIFY_OPTIONAL;
    if (this.rejectUnauthorized == true)
      return Mbedtls.VERIFY_OPTIONAL;
    return Mbedtls.VERIFY_NONE;
  }
}
#end
