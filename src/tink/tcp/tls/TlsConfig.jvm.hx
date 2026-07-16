package tink.tcp.tls;

import java.javax.net.ssl.*;
import tink.tcp.Tls.TlsClientOptions;
import tink.tcp.Tls.TlsServerOptions;
import tink.tcp.tls.TlsAuth.TlsAuthMode;
import tink.tcp.tls.java.JavaSsl;
import tink.tcp.tls.java.JavaTlsPem;
import tink.tcp.tls.java.TrustAllManager;

private class TlsConfigData {
  final ctx:SSLContext;
  final isClient:Bool;
  final servername:Null<String>;
  final alpn:Null<Array<String>>;
  final rejectUnauthorized:Bool;
  final serverAuth:TlsAuthMode;

  function new(
    ctx:SSLContext,
    isClient:Bool,
    serverAuth:TlsAuthMode,
    ?servername:String,
    ?alpn:Array<String>,
    rejectUnauthorized:Bool = true
  ) {
    this.ctx = ctx;
    this.isClient = isClient;
    this.servername = servername;
    this.alpn = alpn;
    this.rejectUnauthorized = rejectUnauthorized;
    this.serverAuth = serverAuth;
  }

  public static function fromClient(options:TlsClientOptions):TlsConfigData {
    final ctx = SSLContext.getInstance("TLS");
    final keyManagers = if (options.key != null && options.cert != null) {
      final ks = JavaTlsPem.keyStoreFromCertKey(options.cert, options.key);
      final kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
      kmf.init(ks, JavaTlsPem.storePassword());
      kmf.getKeyManagers();
    } else null;
    final trustManagers = switch TlsAuth.clientMode(options) {
      case None:
        JavaSsl.trustManagerArray(new TrustAllManager());
      case Required:
        final ts = JavaTlsPem.trustStoreFromCa(options.ca);
        final tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(ts);
        tmf.getTrustManagers();
      case Optional:
        null;
    };
    ctx.init(keyManagers, trustManagers, new java.security.SecureRandom());
    return new TlsConfigData(
      ctx,
      true,
      None,
      options.servername,
      options.alpn,
      options.rejectUnauthorized != false
    );
  }

  public static function fromServer(options:TlsServerOptions):TlsConfigData {
    final ctx = SSLContext.getInstance("TLS");
    final ks = JavaTlsPem.keyStoreFromCertKey(options.cert, options.key);
    final kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
    kmf.init(ks, JavaTlsPem.storePassword());
    final trustManagers = if (options.ca != null) {
      final ts = JavaTlsPem.trustStoreFromCa(options.ca);
      final tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
      tmf.init(ts);
      tmf.getTrustManagers();
    } else null;
    ctx.init(kmf.getKeyManagers(), trustManagers, new java.security.SecureRandom());
    return new TlsConfigData(ctx, false, TlsAuth.serverMode(options), null, options.alpn);
  }

  public function createContext(?host:String, ?port:Int):TlsContext {
    if (isClient) {
      final engine = ctx.createSSLEngine(host, port ?? 0);
      engine.setUseClientMode(true);
      final params = engine.getSSLParameters();
      if (servername != null) {
        params.setServerNames(java.util.Collections.singletonList((new SNIHostName(servername) : SNIServerName)));
      }
      if (rejectUnauthorized && servername != null)
        params.setEndpointIdentificationAlgorithm("HTTPS");
      if (alpn != null)
        JavaSsl.setApplicationProtocols(params, alpn);
      engine.setSSLParameters(params);
      return engine;
    } else {
      final engine = ctx.createSSLEngine();
      engine.setUseClientMode(false);
      switch serverAuth {
        case Required:
          engine.setNeedClientAuth(true);
        case Optional:
          engine.setWantClientAuth(true);
        case None:
      }
      final params = engine.getSSLParameters();
      if (alpn != null)
        JavaSsl.setApplicationProtocols(params, alpn);
      engine.setSSLParameters(params);
      return engine;
    }
  }
}

abstract TlsConfig(TlsConfigData) from TlsConfigData {
  @:from static function fromClient(options:TlsClientOptions):TlsConfig
    return TlsConfigData.fromClient(options);

  @:from static function fromServer(options:TlsServerOptions):TlsConfig
    return TlsConfigData.fromServer(options);

  public inline function createContext(?host:String, ?port:Int):TlsContext
    return this.createContext(host, port);
}
