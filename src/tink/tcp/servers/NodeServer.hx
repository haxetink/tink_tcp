package tink.tcp.servers;

#if nodejs
import tink.tcp.Server;
import tink.tcp.Server.BindOptions;
import tink.tcp.connections.NodeDuplex;

using tink.CoreApi;

class NodeServer implements ServerObject {
  final native:js.node.net.Server;
  final app:Handler;
  final errorsTrigger:SignalTrigger<Error>;

  public var endpoint(get, never):Endpoint;
  public var errors(get, never):Signal<Error>;

  function get_endpoint() {
    final addr = native.address();
    return {host: addr.address, port: addr.port};
  }

  function get_errors()
    return errorsTrigger;

  private function new(server, app:Handler, secure = false) {
    this.native = server;
    this.app = app;
    this.errorsTrigger = Signal.trigger();
    // Post-bind only: this ctor runs after 'listening', so bind-time 'error'
    // still rejects the bind Promise alone (no Server / errors yet).
    native.on('error', (e:js.lib.Error) -> errorsTrigger.trigger(Error.ofJsError(e)));
    if (secure)
      // Handshake-adjacent; peer never reaches Handler via secureConnection.
      native.on('tlsClientError', (e:js.lib.Error, _) -> errorsTrigger.trigger(Error.ofJsError(e)));
    // A TLS server hands off raw sockets on 'connection' before the handshake completes;
    // the handshaked, encrypted socket is only available via 'secureConnection'.
    native.on(secure ? 'secureConnection' : 'connection', (c:js.node.net.Socket) -> {
      final duplex = new NodeDuplex('Connection from ${c.remoteAddress}', c);
      app.run(duplex);
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
