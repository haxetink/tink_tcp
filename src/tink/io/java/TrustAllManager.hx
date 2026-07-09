#if java
package tink.io.java;

class TrustAllManager implements java.javax.net.ssl.X509TrustManager {
  public function new() {}

  public function checkClientTrusted(chain, authType) {}

  public function checkServerTrusted(chain, authType) {}

  public function getAcceptedIssuers() return null;
}
#end
