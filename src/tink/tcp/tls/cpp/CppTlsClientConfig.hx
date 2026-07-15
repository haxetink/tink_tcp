#if cpp
package tink.tcp.tls.cpp;

import cpp.*;
import tink.tcp.Tls.TlsClientOptions;
import tink.tcp.cpp.mbedtls.Mbedtls;
import tink.tcp.cpp.mbedtls.NativeTls;
import tink.tcp.cpp.mbedtls.NativeTls.TlsConfigPtr;
import tink.tcp.cpp.mbedtls.NativeTls.TlsSslPtr;

abstract CppTlsClientConfig(TlsClientOptions) from TlsClientOptions {
  public function createContext():CppTlsContext {
    final conf = NativeTls.configCreate(0);
    if (conf == null)
      throw new haxe.Exception('mbedtls config create failed');

    if (this.rejectUnauthorized == false)
      NativeTls.configSetAuthmode(conf, Mbedtls.VERIFY_NONE);
    else if (this.ca != null)
      NativeTls.configSetAuthmode(conf, Mbedtls.VERIFY_REQUIRED);
    else
      NativeTls.configSetAuthmode(conf, Mbedtls.VERIFY_NONE);

    if (this.ca != null) {
      final pem = CppTlsPem.asCString(this.ca);
      final r = NativeTls.configSetCaPem(conf, pem, pem.length);
      if (r != 0) {
        NativeTls.configFree(conf);
        throw new haxe.Exception('Failed to parse CA: ${Mbedtls.errorString(r)}');
      }
    }

    if (this.cert != null && this.key != null) {
      CppTlsPem.requirePkcs8(this.key);
      final certPem = CppTlsPem.asCString(this.cert);
      final keyPem = CppTlsPem.asCString(this.key);
      final r = NativeTls.configSetOwnCertPem(conf, certPem, certPem.length, keyPem, keyPem.length);
      if (r != 0) {
        NativeTls.configFree(conf);
        throw new haxe.Exception('Failed to set client cert: ${Mbedtls.errorString(r)}');
      }
    }

    // ALPN: deferred — needs a stable C string table; tests do not exercise it yet.
    if (this.alpn != null && this.alpn.length > 0)
      throw new haxe.Exception('ALPN is not yet supported on the cpp target');

    return new CppTlsContext(conf);
  }

  public function configureSsl(ssl:TlsSslPtr):Void {
    final servername:Null<String> = this.servername;
    if (servername != null) {
      final r = NativeTls.sslSetHostname(ssl, servername);
      if (r != 0)
        throw new haxe.Exception('mbedtls set_hostname failed: ${Mbedtls.errorString(r)}');
    }
  }
}
#end
