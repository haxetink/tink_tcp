package tink.tcp.clients;

#if java
import java.lang.Throwable;
import java.net.InetSocketAddress;
import java.nio.channels.CompletionHandler;
import java.nio.channels.AsynchronousSocketChannel;
import tink.tcp.Client;
import tink.tcp.Client.ConnectOptions;
import tink.tcp.Connection;
import tink.tcp.connections.JavaConnection;
import tink.io.java.OnMainThread;

using tink.CoreApi;

class JavaClient implements Client {
  public function new() {}

  public function connect(to:Endpoint, ?options:ConnectOptions):Promise<Connection> {
    return new Future(cb -> {
      final native = AsynchronousSocketChannel.open();
      var connected = false; // only cancellable before connection completes
      native.connect(to, native, new ConnectedHandler('Connection to $to', outcome -> {
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
  final cb:Callback<Outcome<Connection, Error>>;

  public function new(name, cb) {
    this.name = name;
    this.cb = cb;
  }

  public function completed(result:java.lang.Void, socket:AsynchronousSocketChannel) {
    OnMainThread.run(() -> {
      cb.invoke(Success(new JavaConnection('Connection to ${socket.getRemoteAddress()}', socket)));
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