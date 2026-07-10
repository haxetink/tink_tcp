#if hl
package tink.tcp.tls.hl;

import tink.tcp.Tls.TlsServerOptions;

@:access(sys.ssl.Certificate)
@:access(sys.ssl.Key)
abstract HlTlsServerConfig(TlsServerOptions) from TlsServerOptions {
  public function createContext():HlTlsContext {
    final conf = new sys.ssl.Context.Config(true);
    final ctx = new HlTlsContext(conf);

    final cert = HlTlsPem.parseCert(this.cert);
    final key = HlTlsPem.parseKey(this.key);
    conf.setCert(@:privateAccess cert.__x, @:privateAccess key.__k);
    ctx.retain(cert);
    ctx.retain(key);

    if (this.ca != null) {
      final ca = HlTlsPem.parseCert(this.ca);
      conf.setCa(@:privateAccess ca.__x);
      ctx.retain(ca);
    }

    conf.setVerify(serverVerifyMode());
    return ctx;
  }

  function serverVerifyMode():Int {
    // Same encoding as sys.ssl.Socket: 1=REQUIRED, 2=OPTIONAL, 0=NONE
    if (this.requestCert == true)
      return this.rejectUnauthorized == true ? 1 : 2;
    if (this.rejectUnauthorized == true)
      return 2;
    return 0;
  }
}
#end
