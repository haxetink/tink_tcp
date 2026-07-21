package tink.tcp.tls;

import haxe.io.Bytes;
import java.javax.net.ssl.*;
import tink.tcp.Tls.TlsClientOptions;
import tink.tcp.Tls.TlsServerOptions;
import tink.tcp.tls.TlsAuth.TlsAuthMode;

using tink.CoreApi;

class JvmTlsConfig {
  final ctx:SSLContext;
  final isClient:Bool;
  final servername:Null<String>;
  final alpn:Null<Array<String>>;
  final rejectUnauthorized:Bool;
  final serverAuth:TlsAuthMode;

  function new(ctx:SSLContext, isClient:Bool, serverAuth:TlsAuthMode, ?servername:String, ?alpn:Array<String>, rejectUnauthorized:Bool = true) {
    this.ctx = ctx;
    this.isClient = isClient;
    this.servername = servername;
    this.alpn = alpn;
    this.rejectUnauthorized = rejectUnauthorized;
    this.serverAuth = serverAuth;
  }

  public static function fromClient(options:TlsClientOptions):Outcome<JvmTlsConfig, Error>
    return Error.catchExceptions(() -> {
      final ctx = SSLContext.getInstance("TLS");
      final keyManagers = if (options.key != null && options.cert != null) {
        final ks = keyStoreFromCertKey(options.cert, options.key);
        final kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        kmf.init(ks, storePassword());
        kmf.getKeyManagers();
      } else null;
      final trustManagers = switch TlsAuth.clientMode(options) {
        case None:
          trustManagerArray(new TrustAllManager());
        case Required:
          final ts = trustStoreFromCa(options.ca);
          final tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
          tmf.init(ts);
          tmf.getTrustManagers();
        case Optional:
          null;
      };
      ctx.init(keyManagers, trustManagers, new java.security.SecureRandom());
      return new JvmTlsConfig(
        ctx,
        true,
        None,
        options.servername,
        options.alpn,
        options.rejectUnauthorized != false
      );
    });

  public static function fromServer(options:TlsServerOptions):Outcome<JvmTlsConfig, Error>
    return Error.catchExceptions(() -> {
      final ctx = SSLContext.getInstance("TLS");
      final ks = keyStoreFromCertKey(options.cert, options.key);
      final kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
      kmf.init(ks, storePassword());
      final trustManagers = if (options.ca != null) {
        final ts = trustStoreFromCa(options.ca);
        final tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(ts);
        tmf.getTrustManagers();
      } else null;
      ctx.init(kmf.getKeyManagers(), trustManagers, new java.security.SecureRandom());
      return new JvmTlsConfig(ctx, false, TlsAuth.serverMode(options), null, options.alpn);
    });

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
        setApplicationProtocols(params, alpn);
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
        setApplicationProtocols(params, alpn);
      engine.setSSLParameters(params);
      return engine;
    }
  }

  static function requirePkcs8(pem:Bytes):Void {
    if (pem.toString().indexOf('BEGIN PRIVATE KEY') < 0)
      throw new haxe.Exception('Unsupported key format: expected PKCS#8 PEM (BEGIN PRIVATE KEY)');
  }

  static function parseCertificate(pem:Bytes):java.security.cert.X509Certificate {
    final stream = new java.io.ByteArrayInputStream(pem.getData());
    final factory = java.security.cert.CertificateFactory.getInstance("X.509");
    return cast factory.generateCertificate(stream);
  }

  static function parsePrivateKey(pem:Bytes):java.security.PrivateKey {
    requirePkcs8(pem);
    final decoded = haxe.crypto.Base64.decode(stripPemBody(pem.toString()));
    final spec = new java.security.spec.PKCS8EncodedKeySpec(decoded.getData());
    final factory = java.security.KeyFactory.getInstance("RSA");
    return factory.generatePrivate(spec);
  }

  static function keyStoreFromCertKey(cert:Bytes, key:Bytes, ?alias = "key"):java.security.KeyStore {
    final ks = java.security.KeyStore.getInstance("PKCS12");
    ks.load(null, null);
    ks.setKeyEntry(alias, parsePrivateKey(key), emptyPassword(), certificateChain(parseCertificate(cert)));
    return ks;
  }

  static function trustStoreFromCa(ca:Bytes, ?alias = "ca"):java.security.KeyStore {
    final ks = java.security.KeyStore.getInstance("PKCS12");
    ks.load(null, null);
    ks.setCertificateEntry(alias, parseCertificate(ca));
    return ks;
  }

  static function storePassword() {
    final s:String = "changeit";
    return untyped s.toCharArray();
  }

  static function emptyPassword() return storePassword();

  static function certificateChain(cert:java.security.cert.X509Certificate) {
    final cls = java.lang.Class.forName("java.security.cert.Certificate", true, null);
    final arr = java.lang.reflect.Array.newInstance(cls, 1);
    java.lang.reflect.Array.set(arr, 0, cert);
    return arr;
  }

  static function stripPemBody(text:String):String {
    final lines = text.split("\n");
    final buf = new StringBuf();
    for(line in lines) {
      final trimmed = StringTools.trim(line);
      if (trimmed.length == 0 || trimmed.indexOf("-----") == 0) continue;
      buf.add(trimmed);
    }
    return buf.toString();
  }

  static function setApplicationProtocols(params:SSLParameters, protocols:Array<String>):Void {
    if (protocols == null || protocols.length == 0) return;
    final cls = java.lang.Class.forName("java.lang.String", true, null);
    final arr = java.lang.reflect.Array.newInstance(cls, protocols.length);
    for(i in 0...protocols.length)
      java.lang.reflect.Array.set(arr, i, protocols[i]);
    untyped params.setApplicationProtocols(arr);
  }

  static function trustManagerArray(tm:TrustManager):Dynamic {
    final cls = java.lang.Class.forName("javax.net.ssl.TrustManager", true, null);
    final arr = java.lang.reflect.Array.newInstance(cls, 1);
    java.lang.reflect.Array.set(arr, 0, tm);
    return arr;
  }
}

class TrustAllManager implements X509TrustManager {
  public function new() {}

  public function checkClientTrusted(chain, authType) {}

  public function checkServerTrusted(chain, authType) {}

  public function getAcceptedIssuers() return null;
}