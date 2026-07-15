#if hl
package tink.tcp.tls.hl;

import tink.tcp.Tls.TlsServerOptions;
import tink.tcp.tls.TlsAuth;

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

    conf.setVerify(switch TlsAuth.serverMode(this) {
      case Required: 1;
      case Optional: 2;
      case None: 0;
    });
    return ctx;
  }
}
#end
