#if java
package tink.tcp.tls.java;

import java.javax.net.ssl.*;

class JavaSsl {
  public static function setApplicationProtocols(params:SSLParameters, protocols:Array<String>):Void {
    if (protocols == null || protocols.length == 0) return;
    final cls = java.lang.Class.forName("java.lang.String", true, null);
    final arr = java.lang.reflect.Array.newInstance(cls, protocols.length);
    for (i in 0...protocols.length)
      java.lang.reflect.Array.set(arr, i, protocols[i]);
    untyped params.setApplicationProtocols(arr);
  }

  public static function trustManagerArray(tm:TrustManager):Dynamic {
    final cls = java.lang.Class.forName("javax.net.ssl.TrustManager", true, null);
    final arr = java.lang.reflect.Array.newInstance(cls, 1);
    java.lang.reflect.Array.set(arr, 0, tm);
    return arr;
  }
}
#end
