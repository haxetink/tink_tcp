package tink.tcp.servers;

#if nodejs
import tink.tcp.Server;
import tink.tcp.Server.BindOptions;
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

  public function new(server, secure = false) {
    this.native = server;
    final t = Signal.trigger();
    // A TLS server hands off raw sockets on 'connection' before the handshake completes;
    // the handshaked, encrypted socket is only available via 'secureConnection'.
    native.on(secure ? 'secureConnection' : 'connection', (c:js.node.net.Socket) -> {
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

  static public function bind(target:Endpoint, ?options:BindOptions) {
    final tls = options?.tls;
    final server:js.node.net.Server = if (tls != null) {
      final opts:Dynamic = {
        cert: js.node.Buffer.hxFromBytes(tls.cert),
        key: js.node.Buffer.hxFromBytes(tls.key),
      };
      if (tls.ca != null) opts.ca = [js.node.Buffer.hxFromBytes(tls.ca)];
      if (tls.requestCert != null) opts.requestCert = tls.requestCert;
      if (tls.rejectUnauthorized != null) opts.rejectUnauthorized = tls.rejectUnauthorized;
      if (tls.alpn != null) opts.ALPNProtocols = tls.alpn;
      js.node.Tls.createServer(cast opts);
    } else {
      js.node.Net.createServer();
    }
    return
      new Future(cb -> {
        server.on('listening', _ -> cb(Success((new NodeServer(server, tls != null) : Server))));
        server.on('error', e -> cb(Failure(new Error('Failed to open server on $target because $e'))));
        server.listen(target.port, target.host);
        return server.close;
      });
  }
}
#end