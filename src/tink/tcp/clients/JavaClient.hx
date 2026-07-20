package tink.tcp.clients;

#if java
import java.lang.Throwable;
import java.nio.channels.CompletionHandler;
import java.nio.channels.AsynchronousSocketChannel;
import tink.tcp.Client.ConnectOptions;
import tink.tcp.connections.JavaConnection;
import tink.tcp.connections.JavaTlsConnection;
import tink.tcp.tls.TlsConfig;
import tink.io.java.JavaTlsSession;
import tink.io.java.OnMainThread;

using tink.CoreApi;
using tink.io.Source;

class JavaClient {
  private function new() {}

  static public function connect(to:Endpoint, app:Handler, ?options:ConnectOptions):Promise<Noise> {
    return new Future(cb -> {
      final native = AsynchronousSocketChannel.open();
      var settled = false;
      native.connect(to, native, new ConnectedHandler(to, options, app, outcome -> {
        settled = true;
        cb(outcome);
      }));
      return () -> if (!settled) {
        try native.close()
        catch (_:Dynamic) {}
      };
    });
  }
}

private class ConnectedHandler implements CompletionHandler<java.lang.Void, AsynchronousSocketChannel> {
  final to:Endpoint;
  final options:ConnectOptions;
  final app:Handler;
  final cb:Callback<Outcome<Noise, Error>>;

  public function new(to, ?options, app, cb) {
    this.to = to;
    this.options = options;
    this.app = app;
    this.cb = cb;
  }

  function start(source, sink, local, peer) {
    app({source: source, local: local, peer: peer})
      .pipeTo(sink, {end: true})
      .handle(_ -> {});
    cb.invoke(Success(Noise));
  }

  public function completed(result:java.lang.Void, socket:AsynchronousSocketChannel) {
    OnMainThread.run(() -> {
      final tls = options?.tls;
      if (tls == null) {
        final duplex = new JavaConnection('Connection to ${socket.getRemoteAddress()}', socket);
        start(duplex.source, duplex.sink, duplex.local, duplex.peer);
      } else {
        switch TlsConfig.fromClient(tls) {
          case Failure(e):
            try socket.close()
            catch (_:Dynamic) {}
            cb.invoke(Failure(e));
          case Success(tlsCfg):
            try {
              final tlsSession = new JavaTlsSession(tlsCfg, socket, to.host, to.port);
              tlsSession.handshake().next(_ -> tlsSession).handle(o -> switch o {
                case Success(s):
                  final duplex = new JavaTlsConnection('Connection to ${socket.getRemoteAddress()}', s);
                  start(duplex.source, duplex.sink, duplex.local, duplex.peer);
                case Failure(e):
                  try socket.close()
                  catch (_:Dynamic) {}
                  cb.invoke(Failure(e));
              });
            } catch (e:haxe.Exception) {
              try socket.close()
              catch (_:Dynamic) {}
              cb.invoke(Failure(Error.withData(e.message, e)));
            }
        }
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
#end
