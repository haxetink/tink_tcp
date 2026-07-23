package tink.tcp.clients;

#if nodejs
import tink.tcp.Client.ConnectOptions;
import tink.tcp.connections.NodeConnection;

using tink.CoreApi;

class NodeClient {
  private function new() {}

  static public function connect(to:Endpoint, app:Handler, ?options:ConnectOptions):Promise<Noise> {
    return new Promise((resolve, reject) -> {
      var done = false;
      function finish(f:Void->Void) {
        if (!done) {
          done = true;
          f();
        }
      }
      final tls = options?.tls;
      final native:js.node.net.Socket = if (tls != null) {
        final opts:Dynamic = {port: to.port, host: to.host};
        if (tls.ca != null) opts.ca = [js.node.Buffer.hxFromBytes(tls.ca)];
        if (tls.cert != null) opts.cert = js.node.Buffer.hxFromBytes(tls.cert);
        if (tls.key != null) opts.key = js.node.Buffer.hxFromBytes(tls.key);
        if (tls.servername != null) opts.servername = tls.servername;
        if (tls.rejectUnauthorized != null) opts.rejectUnauthorized = tls.rejectUnauthorized;
        if (tls.alpn != null) opts.ALPNProtocols = tls.alpn;
        js.node.Tls.connect(cast opts);
      } else {
        js.node.Net.connect(to.port, to.host);
      }
      final event = tls != null ? 'secureConnect' : 'connect';
      native.once(event, () -> finish(() -> {
        final duplex = new NodeConnection('Connection to $to', native);
        app.run(duplex);
        resolve(Noise);
      }));
      native.once('error', e -> finish(() -> reject(Error.ofJsError(e))));
      return function() {
        if (!done) {
          done = true;
          native.destroy();
        }
      };
    });
  }
}
#end
