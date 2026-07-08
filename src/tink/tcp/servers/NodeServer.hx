package tink.tcp.servers;

#if nodejs
import tink.tcp.Server;
import tink.tcp.Connection;
import tink.tcp.connections.NodeConnection;
import tink.io.Source;
import tink.io.Sink;

using tink.CoreApi;

class NodeServer implements ServerObject {
  final native:js.node.net.Server;
  public final connected:Signal<Connection>;

  public var port(get, never):Int;

  function get_port() {
    final addr = native.address();
    return addr.port;
  }

  public function new(server) {
    this.native = server;
    final t = Signal.trigger();
    native.on('connection', (c:js.node.net.Socket) -> {
      t.trigger((new NodeConnection('Connection from ${c.remoteAddress}', c) : Connection));
    });
    connected = t;
  }

  public function close():Promise<Noise> {
    return new Promise((resolve, reject) -> {
      native.close(cast((e:js.Error) -> if (e == null) resolve(Noise) else reject(Error.ofJsError(e))));
      return null;
    });
  }

  static public function bind(target:Endpoint) {
    final server = js.node.Net.createServer();
    return
      Future.async(function(cb) {
        server.on('listening', _ -> {
          cb(Success((new NodeServer(server) : Server)));
        });
        server.on('error', e -> {
          cb(Failure(new Error('Failed to open server on $target because $e')));
        });
        server.listen(target.port, target.host);
        return function() {
          server.close();
        };
      });
  }
}
#end
