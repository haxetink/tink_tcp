package tink.tcp.servers;

#if java
import tink.tcp.Server;
import tink.tcp.Connection;
import tink.tcp.connections.JavaConnection;
import java.nio.channels.AsynchronousServerSocketChannel as Native;
import java.nio.channels.AsynchronousSocketChannel;
import java.nio.channels.CompletionHandler;
import java.lang.Throwable;
import tink.io.java.OnMainThread;

using tink.CoreApi;

@:allow(tink.tcp)
class JavaServer implements ServerObject {
  var native:Native;
  var trigger:SignalTrigger<Connection>;
  var _connected:Signal<Connection>;
  public var connected(get, null):Signal<Connection>;
  
  function get_connected()
    return _connected;
  
  public var port(get, never):Int;
  function get_port() {
    var addr:java.net.InetSocketAddress = cast native.getLocalAddress();
    return addr.getPort();
  }
    
  public function new(server) {
    this.native = server;
    _connected = trigger = Signal.trigger();
    server.accept(this, new AcceptedHandler());
  }
  
  public function close():Promise<Noise> {
    native.close();
    return Promise.NOISE;
  }
  
  static public function bind(port:Int) {
    return new Promise(function(resolve, reject) {
      try {
        var server = Native.open();
        server.bind(new java.net.InetSocketAddress('0.0.0.0', port));
        resolve((new JavaServer(server):Server));
      } catch(e:java.io.IOException) {
        reject(Error.withData(e.getMessage(), e));
      }
      return null;
    });
  }
}


private class AcceptedHandler implements CompletionHandler<AsynchronousSocketChannel, JavaServer>  {
  public function new() {}
  
  public function completed(socket:AsynchronousSocketChannel, server:JavaServer) {
    OnMainThread.run(function() {
      server.trigger.trigger(new JavaConnection('Connection from ${socket.getRemoteAddress()}', socket));
      server.native.accept(server, this);
    });
  }
  
  public function failed(exc:Throwable, server:JavaServer) {
    // TODO: handle java.nio.channels.AsynchronousCloseException? it is thrown when server is closed while accept() is still pending
    // TODO: report other errors
  }
}
#end
