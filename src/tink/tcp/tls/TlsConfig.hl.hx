package tink.tcp.tls;

import tink.tcp.Tls.TlsClientOptions;
import tink.tcp.Tls.TlsServerOptions;
import tink.tcp.tls.hl.HlTlsPem;

@:access(sys.ssl.Certificate)
@:access(sys.ssl.Key)
private class TlsConfigData {
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

  public static function fromClient(options:TlsClientOptions):TlsConfigData {
    final conf = new sys.ssl.Context.Config(false);
    final data = new TlsConfigData(conf, options.servername);

    conf.setVerify(switch TlsAuth.clientMode(options) {
      case Required: 1;
      case Optional | None: 0;
    });

    if (options.ca != null) {
      final ca = HlTlsPem.parseCert(options.ca);
      conf.setCa(@:privateAccess ca.__x);
      data.retain(ca);
    }

    if (options.cert != null && options.key != null) {
      final cert = HlTlsPem.parseCert(options.cert);
      final key = HlTlsPem.parseKey(options.key);
      conf.setCert(@:privateAccess cert.__x, @:privateAccess key.__k);
      data.retain(cert);
      data.retain(key);
    }

    return data;
  }

  public static function fromServer(options:TlsServerOptions):TlsConfigData {
    final conf = new sys.ssl.Context.Config(true);
    final data = new TlsConfigData(conf);

    final cert = HlTlsPem.parseCert(options.cert);
    final key = HlTlsPem.parseKey(options.key);
    conf.setCert(@:privateAccess cert.__x, @:privateAccess key.__k);
    data.retain(cert);
    data.retain(key);

    if (options.ca != null) {
      final ca = HlTlsPem.parseCert(options.ca);
      conf.setCa(@:privateAccess ca.__x);
      data.retain(ca);
    }

    conf.setVerify(switch TlsAuth.serverMode(options) {
      case Required: 1;
      case Optional: 2;
      case None: 0;
    });

    return data;
  }

  public function createContext():TlsContext {
    final ssl = new sys.ssl.Context(conf);
    if (servername != null)
      ssl.setHostname(@:privateAccess servername.toUtf8());
    return ssl;
  }
}

abstract TlsConfig(TlsConfigData) from TlsConfigData {
  @:from static function fromClient(options:TlsClientOptions):TlsConfig
    return TlsConfigData.fromClient(options);

  @:from static function fromServer(options:TlsServerOptions):TlsConfig
    return TlsConfigData.fromServer(options);

  public inline function createContext():TlsContext
    return this.createContext();
}
