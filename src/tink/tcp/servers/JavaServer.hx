package tink.tcp.servers;

#if java
import tink.tcp.Server;
import tink.tcp.Server.BindOptions;
import tink.tcp.connections.JavaConnection;
import tink.tcp.connections.JavaTlsConnection;
import tink.tcp.tls.TlsConfig;
import tink.io.java.JavaTlsSession;
import tink.io.java.OnMainThread;
import java.nio.channels.AsynchronousServerSocketChannel as Native;
import java.nio.channels.AsynchronousSocketChannel;
import java.nio.channels.ClosedChannelException;
import java.nio.channels.CompletionHandler;
import java.lang.Throwable;

using tink.CoreApi;

class JavaServer implements ServerObject {
  final native:Native;
  final app:Handler;
  final tls:Null<TlsConfig>;
  final acceptHandler:AcceptedHandler;

  public var endpoint(get, never):Endpoint;

  function get_endpoint()
    return (native.getLocalAddress() : Endpoint);

  private function new(server:Native, app:Handler, ?tls:TlsConfig) {
    this.native = server;
    this.app = app;
    this.tls = tls;
    this.acceptHandler = new AcceptedHandler();
    acceptNext();
  }

  public function shutdown():Promise<Noise> {
    native.close();
    return Promise.NOISE;
  }

  function acceptNext() {
    try native.accept(this, acceptHandler) catch (e:ClosedChannelException) {}
  }

  function onAccepted(socket:AsynchronousSocketChannel) {
    if (tls == null) {
      final duplex = new JavaConnection('Connection from ${socket.getRemoteAddress()}', socket);
      Session.run(duplex.source, duplex.sink, duplex.local, duplex.peer, app);
      acceptNext();
    } else {
      final tlsSession = new JavaTlsSession(tls, socket);
      tlsSession.handshake().next(_ -> tlsSession).handle(o -> {
        switch o {
          case Success(s):
            final duplex = new JavaTlsConnection('Connection from ${socket.getRemoteAddress()}', s);
            Session.run(duplex.source, duplex.sink, duplex.local, duplex.peer, app);
            acceptNext();
          case Failure(e):
            try socket.close()
            catch (_:Dynamic) {}
            acceptNext();
        }
      });
    }
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

@:access(tink.tcp.servers.JavaServer)
private class AcceptedHandler implements CompletionHandler<AsynchronousSocketChannel, JavaServer> {
  public function new() {}

  public function completed(socket:AsynchronousSocketChannel, server:JavaServer) {
    OnMainThread.run(() -> server.onAccepted(socket));
  }

  public function failed(exc:Throwable, server:JavaServer) {
    // Expected when shutdown() closes the listen socket while accept() is pending
    // (AsynchronousCloseException) or accept is re-armed on an already-closed channel
    // (ClosedChannelException; AsynchronousCloseException extends it).
    if (Std.isOfType(exc, ClosedChannelException))
      return;
    // TODO: report other accept errors
  }
}
#end
