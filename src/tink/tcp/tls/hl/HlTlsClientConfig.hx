#if hl
package tink.tcp.tls.hl;

import tink.tcp.Tls.TlsClientOptions;
import tink.tcp.tls.TlsAuth;

@:access(sys.ssl.Certificate)
@:access(sys.ssl.Key)
abstract HlTlsClientConfig(TlsClientOptions) from TlsClientOptions {
  public function createContext():HlTlsContext {
    final conf = new sys.ssl.Context.Config(false);

    conf.setVerify(switch TlsAuth.clientMode(this) {
      case Required: 1;
      case Optional | None: 0;
    });

    final ctx = new HlTlsContext(conf);

    if (this.ca != null) {
      final ca = HlTlsPem.parseCert(this.ca);
      conf.setCa(@:privateAccess ca.__x);
      ctx.retain(ca);
    }

    if (this.cert != null && this.key != null) {
      final cert = HlTlsPem.parseCert(this.cert);
      final key = HlTlsPem.parseKey(this.key);
      conf.setCert(@:privateAccess cert.__x, @:privateAccess key.__k);
      ctx.retain(cert);
      ctx.retain(key);
    }

    return ctx;
  }

  public function configureSsl(ssl:sys.ssl.Context):Void {
    if (this.servername != null)
      ssl.setHostname(@:privateAccess this.servername.toUtf8());
  }
}
#end
