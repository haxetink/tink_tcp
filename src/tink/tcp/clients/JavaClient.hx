package tink.tcp.clients;

#if java
import java.lang.Throwable;
import java.javax.net.ssl.*;
import java.nio.channels.CompletionHandler;
import java.nio.channels.AsynchronousSocketChannel;
import tink.tcp.Client;
import tink.tcp.Client.ConnectOptions;
import tink.tcp.Connection;
import tink.tcp.Tls.TlsClientOptions;
import tink.tcp.connections.JavaConnection;
import tink.tcp.connections.JavaTlsConnection;
import tink.tcp.tls.java.JavaTlsPem;
import tink.io.java.JavaTlsSession;
import tink.io.java.OnMainThread;

using tink.CoreApi;

class JavaClient implements Client {
  public function new() {}

  public function connect(to:Endpoint, ?options:ConnectOptions):Promise<Connection> {
    return new Future(cb -> {
      final native = AsynchronousSocketChannel.open();
      var connected = false;
      native.connect(to, native, new ConnectedHandler('Connection to $to', to, options, outcome -> {
        connected = true;
        cb(outcome);
      }));
      return () -> if (!connected) {
        try native.close()
        catch (_:Dynamic) {}
      };
    });
  }
}

private class ConnectedHandler implements CompletionHandler<java.lang.Void, AsynchronousSocketChannel> {
  final name:String;
  final to:Endpoint;
  final options:ConnectOptions;
  final cb:Callback<Outcome<Connection, Error>>;

  public function new(name, to, ?options, cb) {
    this.name = name;
    this.to = to;
    this.options = options;
    this.cb = cb;
  }

  public function completed(result:java.lang.Void, socket:AsynchronousSocketChannel) {
    OnMainThread.run(() -> {
      final tls = options?.tls;
      if (tls == null) {
        cb.invoke(Success(new JavaConnection('Connection to ${socket.getRemoteAddress()}', socket)));
      } else {
        final config:JavaTlsClientConfig = tls;
        final ctx = config.createContext();
        final engine = ctx.createSSLEngine(to.host, to.port);
        config.configureEngine(engine);
        final tlsSession = new JavaTlsSession(socket, engine);
        tlsSession.handshake().next(_ -> tlsSession).handle(o -> switch o {
          case Success(s):
            cb.invoke(Success(new JavaTlsConnection('Connection to ${socket.getRemoteAddress()}', s)));
          case Failure(e):
            try socket.close()
            catch (_:Dynamic) {}
            cb.invoke(Failure(e));
        });
      }
    });
  }

  public function failed(exc:Throwable, socket:AsynchronousSocketChannel) {
    OnMainThread.run(() -> {
      try socket.close()
      catch (_:Dynamic) {}
      cb.invoke(Failure(Error.withData('Connection failed, reason: ' + exc.getMessage(), exc)));
    });
  }
}

abstract JavaTlsClientConfig(TlsClientOptions) from TlsClientOptions {
  public function createContext():SSLContext {
    final ctx = SSLContext.getInstance("TLS");
    final keyManagers = if (this.key != null && this.cert != null) {
      final ks = JavaTlsPem.keyStoreFromCertKey(this.cert, this.key);
      final kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
      kmf.init(ks, JavaTlsPem.storePassword());
      kmf.getKeyManagers();
    } else null;
    final trustManagers = if (!this.rejectUnauthorized) JavaSsl.trustManagerArray(new TrustAllManager()) else if (this.ca != null) {
      final ts = JavaTlsPem.trustStoreFromCa(this.ca);
      final tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
      tmf.init(ts);
      tmf.getTrustManagers();
    } else null;
    ctx.init(keyManagers, trustManagers, new java.security.SecureRandom());
    return ctx;
  }

  public function configureEngine(engine:SSLEngine):Void {
    engine.setUseClientMode(true);
    final params = engine.getSSLParameters();
    if (this.servername != null) {
      params.setServerNames(java.util.Collections.singletonList((new SNIHostName(this.servername) : SNIServerName)));
    }
    if (this.rejectUnauthorized != false && this.servername != null)
      params.setEndpointIdentificationAlgorithm("HTTPS");
    if (this.alpn != null)
      JavaSsl.setApplicationProtocols(params, this.alpn);
    engine.setSSLParameters(params);
  }
}

private class TrustAllManager implements X509TrustManager {
  public function new() {}

  public function checkClientTrusted(chain, authType) {}

  public function checkServerTrusted(chain, authType) {}

  public function getAcceptedIssuers() return null;
}

private class JavaSsl {
  public static function setApplicationProtocols(params:SSLParameters, protocols:Array<String>):Void {
    if (protocols == null || protocols.length == 0) return;
    final cls = java.lang.Class.forName("java.lang.String", true, null);
    final arr = java.lang.reflect.Array.newInstance(cls, protocols.length);
    for (i in 0...protocols.length)
      java.lang.reflect.Array.set(arr, i, protocols[i]);
    untyped params.setApplicationProtocols(arr);
  }

  public static function trustManagerArray(tm:TrustManager):Dynamic {
    final cls = java.lang.Class.forName("javax.net.ssl.TrustManager", true, null);
    final arr = java.lang.reflect.Array.newInstance(cls, 1);
    java.lang.reflect.Array.set(arr, 0, tm);
    return arr;
  }
}
#end
