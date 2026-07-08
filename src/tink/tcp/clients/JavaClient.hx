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
    return Future.async(function(cb) {
      final native = AsynchronousSocketChannel.open();
      final remote:InetSocketAddress = new InetSocketAddress(to.host, to.port);
      native.connect(remote, native, new ConnectedHandler('Connection to $to', cb, native));
      return function() {
        try native.close()
        catch (_:Dynamic) {}
      };
    });
  }
}

private class ConnectedHandler implements CompletionHandler<java.lang.Void, AsynchronousSocketChannel> {
  final name:String;
  final cb:Callback<Outcome<Connection, Error>>;
  final socket:AsynchronousSocketChannel;

  public function new(name, cb, socket) {
    this.name = name;
    this.cb = cb;
    this.socket = socket;
  }

  public function completed(result:java.lang.Void, attachment:AsynchronousSocketChannel) {
    OnMainThread.run(() -> {
      cb.invoke(Success(new JavaConnection('Connection to ${socket.getRemoteAddress()}', socket)));
    });
  }

  public function failed(exc:Throwable, attachment:AsynchronousSocketChannel) {
    OnMainThread.run(() -> {
      try socket.close()
      catch (_:Dynamic) {}
      cb.invoke(Failure(Error.withData('Connection failed, reason: ' + exc.getMessage(), exc)));
    });
  }
}
#end