package tink.tcp.servers;

#if java
import tink.tcp.Server;
import tink.tcp.Server.BindOptions;
import tink.tcp.Connection;
import tink.tcp.Tls.TlsServerOptions;
import tink.tcp.connections.JavaConnection;
import tink.tcp.connections.JavaTlsConnection;
import tink.tcp.tls.java.JavaTlsPem;
import tink.io.java.JavaTlsSession;
import tink.io.java.OnMainThread;
import java.nio.channels.AsynchronousServerSocketChannel as Native;
import java.nio.channels.AsynchronousSocketChannel;
import java.nio.channels.CompletionHandler;
import java.lang.Throwable;
import java.javax.net.ssl.*;

using tink.CoreApi;

@:allow(tink.tcp.servers.JavaServer)
class JavaServer implements ServerObject {
  final native:Native;
  final trigger:SignalTrigger<Connection>;
  final tls:Null<JavaTlsServerConfig>;
  final sslContext:Null<SSLContext>;

  public final connected:Signal<Connection>;

  public var port(get, never):Int;

  function get_port() {
    final addr:java.net.InetSocketAddress = cast native.getLocalAddress();
    return addr.getPort();
  }

  public function new(server:Native, ?tls:JavaTlsServerConfig) {
    this.native = server;
    this.tls = tls;
    this.sslContext = tls?.createContext();
    connected = trigger = Signal.trigger();
    server.accept(this, new AcceptedHandler());
  }

  public function close():Promise<Noise> {
    native.close();
    return Promise.NOISE;
  }

  static public function bind(target:Endpoint, ?options:BindOptions):Promise<Server> {
    return try {
      final server = Native.open();
      server.bind(target);
      (new JavaServer(server, options?.tls) : Server);
    } catch (e:java.io.IOException) {
      Error.withData(e.getMessage(), e);
    }
  }
}

private class AcceptedHandler implements CompletionHandler<AsynchronousSocketChannel, JavaServer> {
  public function new() {}

  public function completed(socket:AsynchronousSocketChannel, server:JavaServer) {
    OnMainThread.run(() -> {
      if (server.tls == null) {
        server.trigger.trigger(new JavaConnection('Connection from ${socket.getRemoteAddress()}', socket));
        server.native.accept(server, this);
      } else {
        final engine = server.sslContext.createSSLEngine();
        server.tls.configureEngine(engine);
        final tlsSession = new JavaTlsSession(socket, engine);
        tlsSession.handshake().next(_ -> tlsSession).handle(o -> {
          switch o {
            case Success(s):
              server.trigger.trigger(new JavaTlsConnection('Connection from ${socket.getRemoteAddress()}', s));
              server.native.accept(server, this);
            case Failure(e):
              try socket.close()
              catch (_:Dynamic) {}
              server.native.accept(server, this);
          }
        });
      }
    });
  }

  public function failed(exc:Throwable, server:JavaServer) {
    // TODO: handle java.nio.channels.AsynchronousCloseException? it is thrown when server is closed while accept() is still pending
    // TODO: report other errors
  }
}

abstract JavaTlsServerConfig(TlsServerOptions) from TlsServerOptions {
  public function createContext():SSLContext {
    final ctx = SSLContext.getInstance("TLS");
    final ks = JavaTlsPem.keyStoreFromCertKey(this.cert, this.key);
    final kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
    kmf.init(ks, JavaTlsPem.storePassword());
    final trustManagers = if (this.ca != null) {
      final ts = JavaTlsPem.trustStoreFromCa(this.ca);
      final tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
      tmf.init(ts);
      tmf.getTrustManagers();
    } else null;
    ctx.init(kmf.getKeyManagers(), trustManagers, new java.security.SecureRandom());
    return ctx;
  }

  public function configureEngine(engine:SSLEngine):Void {
    engine.setUseClientMode(false);
    if (this.requestCert == true)
      engine.setNeedClientAuth(true);
    else if (this.rejectUnauthorized == true)
      engine.setWantClientAuth(true);
    final params = engine.getSSLParameters();
    if (this.alpn != null)
      JavaSsl.setApplicationProtocols(params, this.alpn);
    engine.setSSLParameters(params);
  }
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
}
#end
