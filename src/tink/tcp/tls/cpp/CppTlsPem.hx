#if cpp
package tink.tcp.tls.cpp;

import haxe.io.Bytes;
import tink.tcp.tls.TlsPem;

class CppTlsPem {
  public static function asCString(pem:Bytes):String {
    return pem.toString();
  }

  public static function requirePkcs8(pem:Bytes):Void {
    TlsPem.requirePkcs8(pem);
  }
}
#end
