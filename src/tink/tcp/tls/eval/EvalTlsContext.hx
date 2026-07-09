#if eval
package tink.tcp.tls.eval;

import mbedtls.*;

class EvalTlsContext {
  public final conf:Config;
  final entropy:Entropy;
  final drbg:CtrDrbg;

  public function new(conf:Config, entropy:Entropy, drbg:CtrDrbg) {
    this.conf = conf;
    this.entropy = entropy;
    this.drbg = drbg;
  }

  public function newSsl():Ssl {
    final ssl = new Ssl();
    final r = ssl.setup(conf);
    if (r != 0)
      throw new haxe.Exception('mbedtls Ssl.setup failed: ${mbedtls.Error.strerror(r)}');
    return ssl;
  }
}
#end
