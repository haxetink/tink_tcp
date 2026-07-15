#if eval
package tink.tcp.tls.eval;

import mbedtls.*;
import tink.tcp.Tls.TlsServerOptions;
import tink.tcp.tls.TlsAuth;

abstract EvalTlsServerConfig(TlsServerOptions) from TlsServerOptions {
  public function createContext():EvalTlsContext {
    final entropy = new Entropy();
    final drbg = new CtrDrbg();
    final seed = drbg.seed(entropy, 'tink_tcp');
    if (seed != 0)
      throw new haxe.Exception('mbedtls CtrDrbg.seed failed: ${mbedtls.Error.strerror(seed)}');

    final conf = new Config();
    final defaults = conf.defaults(SslEndpoint.SSL_IS_SERVER, SslTransport.SSL_TRANSPORT_STREAM, SslPreset.SSL_PRESET_DEFAULT);
    if (defaults != 0)
      throw new haxe.Exception('mbedtls Config.defaults failed: ${mbedtls.Error.strerror(defaults)}');

    conf.rng(drbg);

    final ownCert = EvalTlsPem.parseCert(this.cert);
    final ownKey = EvalTlsPem.parseKey(this.key, drbg);
    final own = conf.own_cert(ownCert, ownKey);
    if (own != 0)
      throw new haxe.Exception('mbedtls Config.own_cert failed: ${mbedtls.Error.strerror(own)}');

    if (this.ca != null)
      conf.ca_chain(EvalTlsPem.parseCert(this.ca));

    conf.authmode(switch TlsAuth.serverMode(this) {
      case Required: SslAuthmode.SSL_VERIFY_REQUIRED;
      case Optional: SslAuthmode.SSL_VERIFY_OPTIONAL;
      case None: SslAuthmode.SSL_VERIFY_NONE;
    });

    if (this.alpn != null) {
      final r = conf.alpn_protocols(this.alpn);
      if (r != 0)
        throw new haxe.Exception('mbedtls Config.alpn_protocols failed: ${mbedtls.Error.strerror(r)}');
    }

    return new EvalTlsContext(conf, entropy, drbg);
  }
}
#end
