package tink.tcp.tls;

import mbedtls.*;
import tink.tcp.Tls.TlsClientOptions;
import tink.tcp.Tls.TlsServerOptions;
import tink.tcp.tls.eval.EvalTlsPem;

private class TlsConfigData {
  final conf:Config;
  final entropy:Entropy;
  final drbg:CtrDrbg;
  final servername:Null<String>;

  function new(conf:Config, entropy:Entropy, drbg:CtrDrbg, ?servername:String) {
    this.conf = conf;
    this.entropy = entropy;
    this.drbg = drbg;
    this.servername = servername;
  }

  public static function fromClient(options:TlsClientOptions):TlsConfigData {
    final entropy = new Entropy();
    final drbg = new CtrDrbg();
    final seed = drbg.seed(entropy, 'tink_tcp');
    if (seed != 0)
      throw new haxe.Exception('mbedtls CtrDrbg.seed failed: ${mbedtls.Error.strerror(seed)}');

    final conf = new Config();
    final defaults = conf.defaults(SslEndpoint.SSL_IS_CLIENT, SslTransport.SSL_TRANSPORT_STREAM, SslPreset.SSL_PRESET_DEFAULT);
    if (defaults != 0)
      throw new haxe.Exception('mbedtls Config.defaults failed: ${mbedtls.Error.strerror(defaults)}');

    conf.rng(drbg);

    conf.authmode(switch TlsAuth.clientMode(options) {
      case Required: SslAuthmode.SSL_VERIFY_REQUIRED;
      case Optional | None: SslAuthmode.SSL_VERIFY_NONE;
    });

    if (options.ca != null)
      conf.ca_chain(EvalTlsPem.parseCert(options.ca));

    if (options.cert != null && options.key != null) {
      final ownCert = EvalTlsPem.parseCert(options.cert);
      final ownKey = EvalTlsPem.parseKey(options.key, drbg);
      final r = conf.own_cert(ownCert, ownKey);
      if (r != 0)
        throw new haxe.Exception('mbedtls Config.own_cert failed: ${mbedtls.Error.strerror(r)}');
    }

    if (options.alpn != null) {
      final r = conf.alpn_protocols(options.alpn);
      if (r != 0)
        throw new haxe.Exception('mbedtls Config.alpn_protocols failed: ${mbedtls.Error.strerror(r)}');
    }

    return new TlsConfigData(conf, entropy, drbg, options.servername);
  }

  public static function fromServer(options:TlsServerOptions):TlsConfigData {
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

    final ownCert = EvalTlsPem.parseCert(options.cert);
    final ownKey = EvalTlsPem.parseKey(options.key, drbg);
    final own = conf.own_cert(ownCert, ownKey);
    if (own != 0)
      throw new haxe.Exception('mbedtls Config.own_cert failed: ${mbedtls.Error.strerror(own)}');

    if (options.ca != null)
      conf.ca_chain(EvalTlsPem.parseCert(options.ca));

    conf.authmode(switch TlsAuth.serverMode(options) {
      case Required: SslAuthmode.SSL_VERIFY_REQUIRED;
      case Optional: SslAuthmode.SSL_VERIFY_OPTIONAL;
      case None: SslAuthmode.SSL_VERIFY_NONE;
    });

    if (options.alpn != null) {
      final r = conf.alpn_protocols(options.alpn);
      if (r != 0)
        throw new haxe.Exception('mbedtls Config.alpn_protocols failed: ${mbedtls.Error.strerror(r)}');
    }

    return new TlsConfigData(conf, entropy, drbg);
  }

  public function createContext():TlsContext {
    final ssl = new Ssl();
    final r = ssl.setup(conf);
    if (r != 0)
      throw new haxe.Exception('mbedtls Ssl.setup failed: ${mbedtls.Error.strerror(r)}');
    if (servername != null) {
      final hr = ssl.set_hostname(servername);
      if (hr != 0)
        throw new haxe.Exception('mbedtls Ssl.set_hostname failed: ${mbedtls.Error.strerror(hr)}');
    }
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
