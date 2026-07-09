package tink.tcp.servers;

#if java
import tink.tcp.Server;
import tink.tcp.Server.BindOptions;
import tink.tcp.Connection;
import tink.tcp.connections.JavaConnection;
import tink.tcp.connections.JavaTlsConnection;
import tink.io.java.JavaTlsServerConfig;
import tink.io.java.JavaTlsHandshake;
import java.nio.channels.AsynchronousServerSocketChannel as Native;
import java.nio.channels.AsynchronousSocketChannel;
import java.nio.channels.CompletionHandler;
import java.lang.Throwable;
import tink.io.java.OnMainThread;

using tink.CoreApi;

@:allow(tink.tcp)
class JavaServer implements ServerObject {
  final native:Native;
  final trigger:SignalTrigger<Connection>;
  final tls:Null<JavaTlsServerConfig>;
  final sslContext:Null<java.javax.net.ssl.SSLContext>;

  public final connected:Signal<Connection>;

  public var port(get, never):Int;

  function get_port() {
    final addr:java.net.InetSocketAddress = cast native.getLocalAddress();
    return addr.getPort();
  }

  public function new(server, ?tls:JavaTlsServerConfig) {
    this.native = server;
    this.tls = tls;
    this.sslContext = tls == null ? null : tls.createContext();
    connected = trigger = Signal.trigger();
    server.accept(this, new AcceptedHandler());
  }

  public function close():Promise<Noise> {
    native.close();
    return Promise.NOISE;
  }

  static public function bind(target:Endpoint, ?options:BindOptions) {
    return new Promise((resolve, reject) -> {
      try {
        final server = Native.open();
        server.bind(target);
        final tls = options?.tls;
        final config:Null<JavaTlsServerConfig> = tls;
        resolve((new JavaServer(server, config) : Server));
      } catch (e:java.io.IOException) {
        reject(Error.withData(e.getMessage(), e));
      }
      return null;
    });
  }
}

private class AcceptedHandler implements CompletionHandler<AsynchronousSocketChannel, JavaServer> {
  public function new() {}

  public function completed(socket:AsynchronousSocketChannel, server:JavaServer) {
    OnMainThread.run(() -> {
      if (server.tls == null) {
        server.trigger.trigger(new JavaConnection('Connection from ${socket.getRemoteAddress()}', socket));
        server.native.accept(server, this);
        return;
      }
      final engine = server.sslContext.createSSLEngine();
      server.tls.configureEngine(engine);
      JavaTlsHandshake.handshake(socket, engine).handle(o -> {
        switch o {
          case Success(session):
            server.trigger.trigger(new JavaTlsConnection('Connection from ${socket.getRemoteAddress()}', session));
            server.native.accept(server, this);
          case Failure(e):
            try socket.close()
            catch (_:Dynamic) {}
            server.native.accept(server, this);
        }
      });
    });
  }

  public function failed(exc:Throwable, server:JavaServer) {
    // TODO: handle java.nio.channels.AsynchronousCloseException? it is thrown when server is closed while accept() is still pending
    // TODO: report other errors
  }
}
#end
