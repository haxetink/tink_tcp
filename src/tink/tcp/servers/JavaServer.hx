package tink.tcp.servers;

#if java
import tink.tcp.Server;
import tink.tcp.Server.BindOptions;
import tink.tcp.connections.JavaConnection;
import tink.tcp.connections.JavaTlsConnection;
import tink.tcp.tls.TlsConfig;
import tink.io.Source;
import tink.io.Sink;
import tink.io.java.JavaTlsSession;
import tink.io.java.OnMainThread;
import java.nio.channels.AsynchronousServerSocketChannel as Native;
import java.nio.channels.AsynchronousSocketChannel;
import java.nio.channels.CompletionHandler;
import java.lang.Throwable;

using tink.CoreApi;

@:allow(tink.tcp.servers.JavaServer)
class JavaServer implements ServerObject {
  final native:Native;
  final app:Handler;
  final tls:Null<TlsConfig>;

  public var endpoint(get, never):Endpoint;

  function get_endpoint()
    return (native.getLocalAddress() : Endpoint);

  public function new(server:Native, app:Handler, ?tls:TlsConfig) {
    this.native = server;
    this.app = app;
    this.tls = tls;
    server.accept(this, new AcceptedHandler());
  }

  public function shutdown():Promise<Noise> {
    native.close();
    return Promise.NOISE;
  }

  function start(source:RealSource, sink:RealSink, local:Endpoint, peer:Endpoint) {
    Session.run(source, sink, local, peer, app);
  }

  static public function bind(to:Endpoint, app:Handler, ?options:BindOptions):Promise<Server> {
    final tls:Null<TlsConfig> = switch options?.tls {
      case null: null;
      case opts:
        switch TlsConfig.fromServer(opts) {
          case Failure(e): return Future.sync(Failure(e));
          case Success(cfg): cfg;
        }
    };
    return try {
      final server = Native.open();
      server.bind(to);
      (new JavaServer(server, app, tls) : Server);
    } catch (e:haxe.Exception) {
      Error.withData(e.message, e);
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
        final duplex = new JavaConnection('Connection from ${socket.getRemoteAddress()}', socket);
        server.start(duplex.source, duplex.sink, duplex.local, duplex.peer);
        server.native.accept(server, this);
      } else {
        final tlsSession = new JavaTlsSession(server.tls, socket);
        tlsSession.handshake().next(_ -> tlsSession).handle(o -> {
          switch o {
            case Success(s):
              final duplex = new JavaTlsConnection('Connection from ${socket.getRemoteAddress()}', s);
              server.start(duplex.source, duplex.sink, duplex.local, duplex.peer);
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
#end
