package tink.tcp.tls;

import haxe.io.Bytes;

class TlsPem {
  public static function requirePkcs8(pem:Bytes):Void {
    if (pem.toString().indexOf('BEGIN PRIVATE KEY') < 0)
      throw new haxe.Exception('Unsupported key format: expected PKCS#8 PEM (BEGIN PRIVATE KEY)');
  }
}
