#if hl
package tink.tcp.tls.hl;

import sys.ssl.Certificate;
import sys.ssl.Key;

/**
  Shared TLS config + retained cert/key roots so GC does not free mbedtls objects mid-session.
**/
class HlTlsContext {
  public final conf:sys.ssl.Context.Config;
  final roots:Array<Dynamic> = [];

  public function new(conf:sys.ssl.Context.Config) {
    this.conf = conf;
  }

  public function retain(v:Dynamic):Void {
    roots.push(v);
  }

  public function newSsl():sys.ssl.Context {
    return new sys.ssl.Context(conf);
  }
}
#end
