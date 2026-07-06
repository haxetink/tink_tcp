package tink.tcp.servers;

#if nodejs
import tink.tcp.Server;
import tink.tcp.Connection;
import tink.tcp.connections.NodeConnection;
import tink.io.Source;
import tink.io.Sink;

using tink.CoreApi;

class NodeServer implements ServerObject {
  var native:js.node.net.Server;
  var _connected:Signal<Connection>;

  public var connected(get, null):Signal<Connection>;

  function get_connected()
    return _connected;

  public var port(get, never):Int;

  function get_port() {
    var addr = native.address();
    return addr.port;
  }

  public function new(server) {
    this.native = server;
    var t = Signal.trigger();
    native.on('connection', function(c:js.node.net.Socket) {
      t.trigger((new NodeConnection('Connection from ${c.remoteAddress}', c) : Connection));
    });
    _connected = t;
  }

  public function close():Promise<Noise> {
    return new Promise((resolve, reject) -> {
      native.close(cast((e:js.Error) -> if (e == null) resolve(Noise) else reject(Error.ofJsError(e))));
      return null;
    });
  }

  static public function bind(port:Int) {
    var server = js.node.Net.createServer();
    return
      Future.async(function(cb) {
        server.on('listening', function(_) {
          cb(Success((new NodeServer(server) : Server)));
        });
        server.on('error', function(e) {
          cb(Failure(new Error('Failed to open server on port $port because $e')));
        });
        server.listen(port);
        return function() {
          server.close();
        };
      });
  }
}
#end