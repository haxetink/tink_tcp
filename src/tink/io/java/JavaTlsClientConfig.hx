#if java
package tink.io.java;

import tink.tcp.Tls.TlsClientOptions;

abstract JavaTlsClientConfig(TlsClientOptions) from TlsClientOptions {
  public function createContext():java.javax.net.ssl.SSLContext {
    final ctx = java.javax.net.ssl.SSLContext.getInstance("TLS");
    final keyManagers = if (this.key != null && this.cert != null) {
      final ks = JavaTlsPem.keyStoreFromCertKey(this.cert, this.key);
      final kmf = java.javax.net.ssl.KeyManagerFactory.getInstance(java.javax.net.ssl.KeyManagerFactory.getDefaultAlgorithm());
      kmf.init(ks, JavaTlsPem.storePassword());
      kmf.getKeyManagers();
    } else
      null;
    final trustManagers = if (this.rejectUnauthorized == false)
      JavaSsl.trustManagerArray(new TrustAllManager())
    else if (this.ca != null) {
      final ts = JavaTlsPem.trustStoreFromCa(this.ca);
      final tmf = java.javax.net.ssl.TrustManagerFactory.getInstance(java.javax.net.ssl.TrustManagerFactory.getDefaultAlgorithm());
      tmf.init(ts);
      tmf.getTrustManagers();
    } else
      null;
    ctx.init(keyManagers, trustManagers, new java.security.SecureRandom());
    return ctx;
  }

  public function configureEngine(engine:java.javax.net.ssl.SSLEngine):Void {
    engine.setUseClientMode(true);
    final params = engine.getSSLParameters();
    if (this.servername != null) {
      final sni:java.javax.net.ssl.SNIServerName = new java.javax.net.ssl.SNIHostName(this.servername);
      params.setServerNames(java.util.Collections.singletonList(sni));
    }
    if (this.rejectUnauthorized != false && this.servername != null)
      params.setEndpointIdentificationAlgorithm("HTTPS");
    if (this.alpn != null)
      JavaSsl.setApplicationProtocols(params, this.alpn);
    engine.setSSLParameters(params);
  }
}
#end
