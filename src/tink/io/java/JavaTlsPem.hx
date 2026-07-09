#if java
package tink.io.java;

import haxe.io.Bytes;

class JavaTlsPem {
  public static function parseCertificate(pem:Bytes):java.security.cert.X509Certificate {
    final stream = new java.io.ByteArrayInputStream(pem.getData());
    final factory = java.security.cert.CertificateFactory.getInstance("X.509");
    return cast factory.generateCertificate(stream);
  }

  public static function parsePrivateKey(pem:Bytes):java.security.PrivateKey {
    final text = pem.toString();
    if (text.indexOf("BEGIN PRIVATE KEY") < 0)
      throw new haxe.Exception('Unsupported key format: expected PKCS#8 PEM (BEGIN PRIVATE KEY)');
    final decoded = haxe.crypto.Base64.decode(stripPemBody(text));
    final spec = new java.security.spec.PKCS8EncodedKeySpec(decoded.getData());
    final factory = java.security.KeyFactory.getInstance("RSA");
    return factory.generatePrivate(spec);
  }

  public static function keyStoreFromCertKey(cert:Bytes, key:Bytes, ?alias = "key"):java.security.KeyStore {
    final ks = java.security.KeyStore.getInstance("PKCS12");
    ks.load(null, null);
    ks.setKeyEntry(alias, parsePrivateKey(key), emptyPassword(), certificateChain(parseCertificate(cert)));
    return ks;
  }

  public static function trustStoreFromCa(ca:Bytes, ?alias = "ca"):java.security.KeyStore {
    final ks = java.security.KeyStore.getInstance("PKCS12");
    ks.load(null, null);
    ks.setCertificateEntry(alias, parseCertificate(ca));
    return ks;
  }

  public static function storePassword() {
    final s:String = "changeit";
    return untyped s.toCharArray();
  }

  public static function emptyPassword() return storePassword();

  static function certificateChain(cert:java.security.cert.X509Certificate) {
    final cls = java.lang.Class.forName("java.security.cert.Certificate", true, null);
    final arr = java.lang.reflect.Array.newInstance(cls, 1);
    java.lang.reflect.Array.set(arr, 0, cert);
    return arr;
  }

  static function stripPemBody(text:String):String {
    final lines = text.split("\n");
    final buf = new StringBuf();
    for (line in lines) {
      final trimmed = StringTools.trim(line);
      if (trimmed.length == 0 || trimmed.indexOf("-----") == 0) continue;
      buf.add(trimmed);
    }
    return buf.toString();
  }
}
#end
