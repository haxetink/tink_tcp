package tink.tcp.servers;

#if java
import tink.tcp.Server;
import tink.tcp.Server.BindOptions;
import tink.tcp.Connection;
import tink.tcp.connections.JavaConnection;
import tink.tcp.connections.JavaTlsConnection;
import tink.tcp.tls.TlsConfig;
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
  final trigger:SignalTrigger<Connection>;
  final tls:Null<TlsConfig>;

  public final connected:Signal<Connection>;

  public var port(get, never):Int;

  function get_port() {
    final addr:java.net.InetSocketAddress = cast native.getLocalAddress();
    return addr.getPort();
  }

  public function new(server:Native, ?tls:TlsConfig) {
    this.native = server;
    this.tls = tls;
    connected = trigger = Signal.trigger();
    server.accept(this, new AcceptedHandler());
  }

  public function close():Promise<Noise> {
    native.close();
    return Promise.NOISE;
  }

  static public function bind(target:Endpoint, ?options:BindOptions):Promise<Server> {
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
      server.bind(target);
      (new JavaServer(server, tls) : Server);
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
        server.trigger.trigger(new JavaConnection('Connection from ${socket.getRemoteAddress()}', socket));
        server.native.accept(server, this);
      } else {
        final tlsSession = new JavaTlsSession(server.tls, socket);
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
#end
