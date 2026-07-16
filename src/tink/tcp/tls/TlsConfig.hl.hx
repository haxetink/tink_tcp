package tink.tcp.tls;

import haxe.io.Bytes;
import sys.ssl.Certificate;
import sys.ssl.Key;
import tink.tcp.Tls.TlsClientOptions;
import tink.tcp.Tls.TlsServerOptions;
using tink.CoreApi;

@:access(sys.ssl.Certificate)
@:access(sys.ssl.Key)
class TlsConfig {
  final conf:sys.ssl.Context.Config;
  final servername:Null<String>;
  final roots:Array<Dynamic> = [];

  function new(conf:sys.ssl.Context.Config, ?servername:String) {
    this.conf = conf;
    this.servername = servername;
  }

  function retain(v:Dynamic):Void {
    roots.push(v);
  }

  public static function fromClient(options:TlsClientOptions):Outcome<TlsConfig, Error>
    return Error.catchExceptions(() -> {
      final conf = new sys.ssl.Context.Config(false);
      final data = new TlsConfig(conf, options.servername);

      conf.setVerify(switch TlsAuth.clientMode(options) {
        case Required: 1;
        case Optional | None: 0;
      });

      if (options.ca != null) {
        final ca = parseCert(options.ca);
        conf.setCa(@:privateAccess ca.__x);
        data.retain(ca);
      }

      if (options.cert != null && options.key != null) {
        final cert = parseCert(options.cert);
        final key = parseKey(options.key);
        conf.setCert(@:privateAccess cert.__x, @:privateAccess key.__k);
        data.retain(cert);
        data.retain(key);
      }

      return data;
    });

  public static function fromServer(options:TlsServerOptions):Outcome<TlsConfig, Error>
    return Error.catchExceptions(() -> {
      final conf = new sys.ssl.Context.Config(true);
      final data = new TlsConfig(conf);

      final cert = parseCert(options.cert);
      final key = parseKey(options.key);
      conf.setCert(@:privateAccess cert.__x, @:privateAccess key.__k);
      data.retain(cert);
      data.retain(key);

      if (options.ca != null) {
        final ca = parseCert(options.ca);
        conf.setCa(@:privateAccess ca.__x);
        data.retain(ca);
      }

      conf.setVerify(switch TlsAuth.serverMode(options) {
        case Required: 1;
        case Optional: 2;
        case None: 0;
      });

      return data;
    });

  public function createContext():TlsContext {
    final ssl = new sys.ssl.Context(conf);
    if (servername != null)
      ssl.setHostname(@:privateAccess servername.toUtf8());
    return ssl;
  }

  static function requirePkcs8(pem:Bytes):Void {
    if (pem.toString().indexOf('BEGIN PRIVATE KEY') < 0)
      throw new haxe.Exception('Unsupported key format: expected PKCS#8 PEM (BEGIN PRIVATE KEY)');
  }

  static function parseCert(pem:Bytes):Certificate {
    return Certificate.fromString(pem.toString());
  }

  static function parseKey(pem:Bytes):Key {
    requirePkcs8(pem);
    return Key.readPEM(pem.toString(), false);
  }
}
