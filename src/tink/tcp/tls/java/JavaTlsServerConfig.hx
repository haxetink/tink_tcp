#if java
package tink.tcp.tls.java;

import java.javax.net.ssl.*;
import tink.tcp.Tls.TlsServerOptions;
import tink.tcp.tls.TlsAuth;

abstract JavaTlsServerConfig(TlsServerOptions) from TlsServerOptions {
  public function createContext():SSLContext {
    final ctx = SSLContext.getInstance("TLS");
    final ks = JavaTlsPem.keyStoreFromCertKey(this.cert, this.key);
    final kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
    kmf.init(ks, JavaTlsPem.storePassword());
    final trustManagers = if (this.ca != null) {
      final ts = JavaTlsPem.trustStoreFromCa(this.ca);
      final tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
      tmf.init(ts);
      tmf.getTrustManagers();
    } else null;
    ctx.init(kmf.getKeyManagers(), trustManagers, new java.security.SecureRandom());
    return ctx;
  }

  public function configureEngine(engine:SSLEngine):Void {
    engine.setUseClientMode(false);
    switch TlsAuth.serverMode(this) {
      case Required:
        engine.setNeedClientAuth(true);
      case Optional:
        engine.setWantClientAuth(true);
      case None:
    }
    final params = engine.getSSLParameters();
    if (this.alpn != null)
      JavaSsl.setApplicationProtocols(params, this.alpn);
    engine.setSSLParameters(params);
  }
}
#end
