#if java
package tink.tcp.tls.java;

import java.javax.net.ssl.*;
import tink.tcp.Tls.TlsClientOptions;
import tink.tcp.tls.TlsAuth;

abstract JavaTlsClientConfig(TlsClientOptions) from TlsClientOptions {
  public function createContext():SSLContext {
    final ctx = SSLContext.getInstance("TLS");
    final keyManagers = if (this.key != null && this.cert != null) {
      final ks = JavaTlsPem.keyStoreFromCertKey(this.cert, this.key);
      final kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
      kmf.init(ks, JavaTlsPem.storePassword());
      kmf.getKeyManagers();
    } else null;
    final trustManagers = switch TlsAuth.clientMode(this) {
      case None:
        JavaSsl.trustManagerArray(new TrustAllManager());
      case Required:
        final ts = JavaTlsPem.trustStoreFromCa(this.ca);
        final tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(ts);
        tmf.getTrustManagers();
      case Optional:
        null;
    };
    ctx.init(keyManagers, trustManagers, new java.security.SecureRandom());
    return ctx;
  }

  public function configureEngine(engine:SSLEngine):Void {
    engine.setUseClientMode(true);
    final params = engine.getSSLParameters();
    if (this.servername != null) {
      params.setServerNames(java.util.Collections.singletonList((new SNIHostName(this.servername) : SNIServerName)));
    }
    if (this.rejectUnauthorized != false && this.servername != null)
      params.setEndpointIdentificationAlgorithm("HTTPS");
    if (this.alpn != null)
      JavaSsl.setApplicationProtocols(params, this.alpn);
    engine.setSSLParameters(params);
  }
}
#end
