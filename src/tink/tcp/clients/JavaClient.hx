package tink.tcp.clients;

#if java
import java.lang.Throwable;
import java.nio.channels.CompletionHandler;
import java.nio.channels.AsynchronousSocketChannel;
import tink.tcp.Client;
import tink.tcp.Client.ConnectOptions;
import tink.tcp.Connection;
import tink.tcp.connections.JavaConnection;
import tink.tcp.connections.JavaTlsConnection;
import tink.io.java.JavaTlsClientConfig;
import tink.io.java.JavaTlsHandshake;
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
        return;
      }
      final config:JavaTlsClientConfig = tls;
      final ctx = config.createContext();
      final engine = ctx.createSSLEngine(to.host, to.port);
      config.configureEngine(engine);
      JavaTlsHandshake.handshake(socket, engine).handle(o -> switch o {
        case Success(session):
          cb.invoke(Success(new JavaTlsConnection('Connection to ${socket.getRemoteAddress()}', session)));
        case Failure(e):
          try socket.close()
          catch (_:Dynamic) {}
          cb.invoke(Failure(e));
      });
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
