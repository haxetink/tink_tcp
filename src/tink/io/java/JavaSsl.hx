#if java
package tink.io.java;

class JavaSsl {
  public static function setApplicationProtocols(params:java.javax.net.ssl.SSLParameters, protocols:Array<String>):Void {
    if (protocols == null || protocols.length == 0) return;
    final cls = java.lang.Class.forName("java.lang.String", true, null);
    final arr = java.lang.reflect.Array.newInstance(cls, protocols.length);
    for (i in 0...protocols.length)
      java.lang.reflect.Array.set(arr, i, protocols[i]);
    untyped params.setApplicationProtocols(arr);
  }

  public static function setProtocols(params:java.javax.net.ssl.SSLParameters, protocols:Array<String>):Void {
    if (protocols == null || protocols.length == 0) return;
    final cls = java.lang.Class.forName("java.lang.String", true, null);
    final arr = java.lang.reflect.Array.newInstance(cls, protocols.length);
    for (i in 0...protocols.length)
      java.lang.reflect.Array.set(arr, i, protocols[i]);
    untyped params.setProtocols(arr);
  }

  public static function keyManagerArray(km:java.javax.net.ssl.KeyManager):Dynamic {
    final cls = java.lang.Class.forName("javax.net.ssl.KeyManager", true, null);
    final arr = java.lang.reflect.Array.newInstance(cls, 1);
    java.lang.reflect.Array.set(arr, 0, km);
    return arr;
  }

  public static function trustManagerArray(tm:java.javax.net.ssl.TrustManager):Dynamic {
    final cls = java.lang.Class.forName("javax.net.ssl.TrustManager", true, null);
    final arr = java.lang.reflect.Array.newInstance(cls, 1);
    java.lang.reflect.Array.set(arr, 0, tm);
    return arr;
  }
}
#end
