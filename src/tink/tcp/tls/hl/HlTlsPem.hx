#if hl
package tink.tcp.tls.hl;

import haxe.io.Bytes;
import sys.ssl.Certificate;
import sys.ssl.Key;

class HlTlsPem {
  public static function parseCert(pem:Bytes):Certificate {
    return Certificate.fromString(pem.toString());
  }

  public static function parseKey(pem:Bytes):Key {
    final text = pem.toString();
    if (text.indexOf('BEGIN PRIVATE KEY') < 0)
      throw new haxe.Exception('Unsupported key format: expected PKCS#8 PEM (BEGIN PRIVATE KEY)');
    return Key.readPEM(text, false);
  }
}
#end
