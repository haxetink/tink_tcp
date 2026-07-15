#if cpp
package tink.tcp.tls.cpp;

import cpp.Star;
import tink.tcp.cpp.mbedtls.NativeTls;
import tink.tcp.cpp.mbedtls.NativeTls.TlsConfigPtr;
import tink.tcp.cpp.mbedtls.NativeTls.TlsSslPtr;

class CppTlsContext {
  public final conf:TlsConfigPtr;

  public function new(conf:TlsConfigPtr) {
    this.conf = conf;
  }

  public function newSsl():TlsSslPtr {
    final ssl = NativeTls.sslCreate(conf);
    if (ssl == null)
      throw new haxe.Exception('mbedtls ssl setup failed');
    return ssl;
  }

  public function destroy():Void {
    NativeTls.configFree(conf);
  }
}
#end
