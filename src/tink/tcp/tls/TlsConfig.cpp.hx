package tink.tcp.tls;

import tink.tcp.Tls.TlsClientOptions;
import tink.tcp.Tls.TlsServerOptions;
import tink.tcp.cpp.mbedtls.Mbedtls;
import tink.tcp.cpp.mbedtls.NativeTls;
import tink.tcp.cpp.mbedtls.NativeTls.TlsConfigPtr;
import tink.tcp.tls.cpp.CppTlsPem;

private class TlsConfigData {
  final conf:TlsConfigPtr;
  final servername:Null<String>;

  function new(conf:TlsConfigPtr, ?servername:String) {
    this.conf = conf;
    this.servername = servername;
  }

  public static function fromClient(options:TlsClientOptions):TlsConfigData {
    final conf = NativeTls.configCreate(0);
    if (conf == null)
      throw new haxe.Exception('mbedtls config create failed');

    NativeTls.configSetAuthmode(conf, switch TlsAuth.clientMode(options) {
      case Required: Mbedtls.VERIFY_REQUIRED;
      case Optional | None: Mbedtls.VERIFY_NONE;
    });

    if (options.ca != null) {
      final pem = CppTlsPem.asCString(options.ca);
      final r = NativeTls.configSetCaPem(conf, pem, pem.length);
      if (r != 0) {
        NativeTls.configFree(conf);
        throw new haxe.Exception('Failed to parse CA: ${Mbedtls.errorString(r)}');
      }
    }

    if (options.cert != null && options.key != null) {
      CppTlsPem.requirePkcs8(options.key);
      final certPem = CppTlsPem.asCString(options.cert);
      final keyPem = CppTlsPem.asCString(options.key);
      final r = NativeTls.configSetOwnCertPem(conf, certPem, certPem.length, keyPem, keyPem.length);
      if (r != 0) {
        NativeTls.configFree(conf);
        throw new haxe.Exception('Failed to set client cert: ${Mbedtls.errorString(r)}');
      }
    }

    if (options.alpn != null && options.alpn.length > 0)
      throw new haxe.Exception('ALPN is not yet supported on the cpp target');

    return new TlsConfigData(conf, options.servername);
  }

  public static function fromServer(options:TlsServerOptions):TlsConfigData {
    final conf = NativeTls.configCreate(1);
    if (conf == null)
      throw new haxe.Exception('mbedtls config create failed');

    CppTlsPem.requirePkcs8(options.key);
    final certPem = CppTlsPem.asCString(options.cert);
    final keyPem = CppTlsPem.asCString(options.key);
    final own = NativeTls.configSetOwnCertPem(conf, certPem, certPem.length, keyPem, keyPem.length);
    if (own != 0) {
      NativeTls.configFree(conf);
      throw new haxe.Exception('Failed to set server cert: ${Mbedtls.errorString(own)}');
    }

    if (options.ca != null) {
      final caPem = CppTlsPem.asCString(options.ca);
      final r = NativeTls.configSetCaPem(conf, caPem, caPem.length);
      if (r != 0) {
        NativeTls.configFree(conf);
        throw new haxe.Exception('Failed to parse CA: ${Mbedtls.errorString(r)}');
      }
    }

    NativeTls.configSetAuthmode(conf, switch TlsAuth.serverMode(options) {
      case Required: Mbedtls.VERIFY_REQUIRED;
      case Optional: Mbedtls.VERIFY_OPTIONAL;
      case None: Mbedtls.VERIFY_NONE;
    });

    if (options.alpn != null && options.alpn.length > 0)
      throw new haxe.Exception('ALPN is not yet supported on the cpp target');

    return new TlsConfigData(conf);
  }

  public function createContext():TlsContext {
    final ssl = NativeTls.sslCreate(conf);
    if (ssl == null)
      throw new haxe.Exception('mbedtls ssl setup failed');
    if (servername != null) {
      final r = NativeTls.sslSetHostname(ssl, servername);
      if (r != 0)
        throw new haxe.Exception('mbedtls set_hostname failed: ${Mbedtls.errorString(r)}');
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
