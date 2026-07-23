package tink.tcp.servers;

#if nodejs
import tink.tcp.Server;
import tink.tcp.Server.BindOptions;
import tink.tcp.connections.NodeDuplex;

using tink.CoreApi;

class NodeServer implements ServerObject {
  final native:js.node.net.Server;
  final app:Handler;

  public var endpoint(get, never):Endpoint;

  function get_endpoint() {
    final addr = native.address();
    return {host: addr.address, port: addr.port};
  }

  private function new(server, app:Handler, secure = false) {
    this.native = server;
    this.app = app;
    // A TLS server hands off raw sockets on 'connection' before the handshake completes;
    // the handshaked, encrypted socket is only available via 'secureConnection'.
    native.on(secure ? 'secureConnection' : 'connection', (c:js.node.net.Socket) -> {
      final duplex = new NodeDuplex('Connection from ${c.remoteAddress}', c);
      Session.run(duplex.source, duplex.sink, duplex.local, duplex.peer, this.app, duplex.abort);
    });
  }

  public function shutdown():Promise<Noise> {
    return new Promise((resolve, reject) -> {
      native.close(cast((e:js.lib.Error) -> if (e == null) resolve(Noise) else reject(Error.ofJsError(e))));
      return null;
    });
  }

  static public function bind(to:Endpoint, app:Handler, ?options:BindOptions):Promise<Server> {
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
      Future.irreversible(cb -> {
        server.on('listening', _ -> cb(Success((new NodeServer(server, app, tls != null) : Server))));
        server.on('error', e -> cb(Failure(new Error('Failed to open server on $to because $e'))));
        server.listen(to.port, to.host);
      });
  }
}
#end
