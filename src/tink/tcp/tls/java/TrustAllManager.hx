#if java
package tink.tcp.tls.java;

import java.javax.net.ssl.X509TrustManager;

class TrustAllManager implements X509TrustManager {
  public function new() {}

  public function checkClientTrusted(chain, authType) {}

  public function checkServerTrusted(chain, authType) {}

  public function getAcceptedIssuers() return null;
}
#end
