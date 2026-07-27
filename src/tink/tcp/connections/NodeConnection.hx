package tink.tcp.connections;

#if nodejs
import tink.io.Source;
import tink.io.Sink;

/** Internal duplex plumbing for Handler.run. */
@:allow(tink.tcp.clients.NodeClient)
@:allow(tink.tcp.servers.NodeServer)
class NodeConnection implements Connection {
  public final source:RealSource;
  public final sink:RealSink;
  public final local:Endpoint;
  public final peer:Endpoint;
  private final native:js.node.net.Socket;
  private var aborted = false;

  private function new(name:String, native:js.node.net.Socket) {
    this.native = native;
    local = {host: native.localAddress, port: native.localPort};
    peer = {host: native.remoteAddress, port: native.remotePort};
    source = Source.ofNodeStream('Incoming stream of $name', native);
    sink = Sink.ofNodeStream('Outcoming stream of $name', native);
  }

  /** Best-effort hard-close; same spirit as dial-cancel (`destroy`, not `resetAndDestroy`). */
  public function abort():Void {
    if (aborted)
      return;
    aborted = true;
    native.destroy();
  }
}
#end
