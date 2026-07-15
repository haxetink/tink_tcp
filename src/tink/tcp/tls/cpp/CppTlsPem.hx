#if cpp
package tink.tcp.tls.cpp;

import haxe.io.Bytes;

class CppTlsPem {
  public static function asCString(pem:Bytes):String {
    return pem.toString();
  }

  public static function requirePkcs8(pem:Bytes):Void {
    if (pem.toString().indexOf('BEGIN PRIVATE KEY') < 0)
      throw new haxe.Exception('Unsupported key format: expected PKCS#8 PEM (BEGIN PRIVATE KEY)');
  }
}
#end
