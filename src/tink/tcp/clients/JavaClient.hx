package tink.tcp.clients;

#if java
import java.lang.Throwable;
import java.nio.channels.CompletionHandler;
import java.nio.channels.AsynchronousSocketChannel;
import tink.tcp.Client.ConnectOptions;
import tink.tcp.connections.Connection;
import tink.tcp.connections.JavaConnection;
import tink.tcp.connections.TcpConnection;
import tink.tcp.tls.TlsConfig;
import tink.io.java.JavaTlsSession;
import tink.io.java.OnMainThread;

using tink.CoreApi;

class JavaClient {
  private function new() {}

  static public function connect(to:Endpoint, app:Handler, ?options:ConnectOptions):Promise<Noise> {
    return new Promise((resolve, reject) -> {
      final native = AsynchronousSocketChannel.open();
      var done = false;
      function finish(f:Void->Void) {
        if (!done) {
          done = true;
          f();
        }
      }
      native.connect(to, native, new ConnectedHandler(to, options, app, outcome -> finish(() -> switch outcome {
        case Success(_): resolve(Noise);
        case Failure(e): reject(e);
      })));
      return () -> if (!done) {
        done = true;
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

  function start(duplex:Connection) {
    app.run(duplex);
    cb.invoke(Success(Noise));
  }

  public function completed(result:java.lang.Void, socket:AsynchronousSocketChannel) {
    OnMainThread.run(() -> {
      final tls = options?.tls;
      if (tls == null) {
        start(new JavaConnection('Connection to ${socket.getRemoteAddress()}', socket));
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
                  start(new TcpConnection('Connection to ${socket.getRemoteAddress()}', s));
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
