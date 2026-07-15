#if hl
package tink.tcp.tls.hl;

import haxe.io.Bytes;
import sys.ssl.Certificate;
import sys.ssl.Key;
import tink.tcp.tls.TlsPem;

class HlTlsPem {
  public static function parseCert(pem:Bytes):Certificate {
    return Certificate.fromString(pem.toString());
  }

  public static function parseKey(pem:Bytes):Key {
    TlsPem.requirePkcs8(pem);
    return Key.readPEM(pem.toString(), false);
  }
}
#end
