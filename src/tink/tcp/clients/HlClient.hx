#if hl
package tink.tcp.clients;

import hl.uv.Loop;
import hl.uv.Tcp;
import sys.net.Host;
import tink.tcp.Client.ConnectOptions;
import tink.tcp.connections.HlConnection;
import tink.tcp.connections.HlTlsConnection;
import tink.tcp.hl.HlLoop;
import tink.tcp.tls.TlsConfig;
import tink.io.hl.HlTlsSession;

using tink.CoreApi;

class HlClient {
  private function new() {}

  static public function connect(to:Endpoint, app:Handler, ?options:ConnectOptions, ?loop:Loop):Promise<Noise> {
    final l = loop ?? HlLoop.current();
    return new Promise((resolve, reject) -> {
      final tcp = new Tcp(l);
      final host = try new Host(to.host) catch (e:Dynamic) {
        tcp.close();
        reject(new Error('Failed to resolve ${to.host}: $e'));
        return null;
      };

      tcp.connect(host, to.port, ok -> {
        if (!ok) {
          tcp.close();
          reject(new Error('Failed to connect to $to'));
          return;
        }
        final tls = options?.tls;
        if (tls == null) {
          final duplex = new HlConnection('Connection to $to', tcp, null, to);
          Session.run(duplex.source, duplex.sink, duplex.local, duplex.peer, app);
          resolve(Noise);
        } else {
          switch TlsConfig.fromClient(tls) {
            case Failure(e):
              tcp.close();
              reject(e);
            case Success(tlsCfg):
              try {
                final session = new HlTlsSession(tlsCfg, tcp);
                session.handshake().handle(o -> switch o {
                  case Success(_):
                    final duplex = new HlTlsConnection('Connection to $to', session, null, to);
                    Session.run(duplex.source, duplex.sink, duplex.local, duplex.peer, app);
                    resolve(Noise);
                  case Failure(e):
                    tcp.close();
                    reject(e);
                });
              } catch (e:haxe.Exception) {
                tcp.close();
                reject(Error.withData(e.message, e));
              }
          }
        }
      });
      return null;
    });
  }
}
#end
