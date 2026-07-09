#if java
package tink.io.java;

import tink.tcp.Tls.TlsServerOptions;

abstract JavaTlsServerConfig(TlsServerOptions) from TlsServerOptions {
  public function createContext():java.javax.net.ssl.SSLContext {
    final ctx = java.javax.net.ssl.SSLContext.getInstance("TLS");
    final ks = JavaTlsPem.keyStoreFromCertKey(this.cert, this.key);
    final kmf = java.javax.net.ssl.KeyManagerFactory.getInstance(java.javax.net.ssl.KeyManagerFactory.getDefaultAlgorithm());
    kmf.init(ks, JavaTlsPem.storePassword());
    final trustManagers = if (this.ca != null) {
      final ts = JavaTlsPem.trustStoreFromCa(this.ca);
      final tmf = java.javax.net.ssl.TrustManagerFactory.getInstance(java.javax.net.ssl.TrustManagerFactory.getDefaultAlgorithm());
      tmf.init(ts);
      tmf.getTrustManagers();
    } else
      null;
    ctx.init(kmf.getKeyManagers(), trustManagers, new java.security.SecureRandom());
    return ctx;
  }

  public function configureEngine(engine:java.javax.net.ssl.SSLEngine):Void {
    engine.setUseClientMode(false);
    if (this.requestCert == true)
      engine.setNeedClientAuth(true);
    else if (this.rejectUnauthorized == true)
      engine.setWantClientAuth(true);
    final params = engine.getSSLParameters();
    if (this.alpn != null)
      JavaSsl.setApplicationProtocols(params, this.alpn);
    engine.setSSLParameters(params);
  }
}
#end
