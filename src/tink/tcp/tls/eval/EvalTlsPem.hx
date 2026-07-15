#if eval
package tink.tcp.tls.eval;

import haxe.io.Bytes;
import mbedtls.*;
import tink.tcp.tls.TlsPem;

class EvalTlsPem {
  public static function parseCert(pem:Bytes):X509Crt {
    final cert = new X509Crt();
    final r = cert.parse(pem);
    if (r != 0)
      throw new haxe.Exception('Failed to parse certificate: ${mbedtls.Error.strerror(r)}');
    return cert;
  }

  public static function parseKey(pem:Bytes, drbg:CtrDrbg):PkContext {
    TlsPem.requirePkcs8(pem);
    final key = new PkContext();
    final r = key.parse_key(pem, null, drbg);
    if (r != 0)
      throw new haxe.Exception('Failed to parse private key: ${mbedtls.Error.strerror(r)}');
    return key;
  }
}
#end
