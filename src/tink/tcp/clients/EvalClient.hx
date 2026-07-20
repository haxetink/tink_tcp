#if eval
package tink.tcp.clients;

import eval.luv.*;
import tink.tcp.Client.ConnectOptions;
import tink.tcp.connections.EvalConnection;
import tink.tcp.connections.EvalTlsConnection;
import tink.tcp.eval.EvalLoop;
import tink.tcp.tls.TlsConfig;
import tink.io.eval.EvalTlsSession;

using tink.CoreApi;
using tink.io.Source;

class EvalClient {
  private function new() {}

  static public function connect(to:Endpoint, app:Handler, ?options:ConnectOptions, ?loop:Loop):Promise<Noise> {
    final l = loop ?? EvalLoop.current();
    final addr = switch SockAddr.ipv4(to.host, to.port) {
      case Ok(addr): addr;
      case Error(e):
        return luvError(e, 'Failed to parse address ${to.host}:${to.port}');
    };

    return new Promise((resolve, reject) -> {
      final tcp = switch Tcp.init(l) {
        case Error(e):
          reject(luvError(e, 'Failed to init TCP client'));
          return null;
        case Ok(v): v;
      };

      tcp.connect(addr, function(result) {
        switch result {
          case Error(e):
            Handle.close(tcp, noop);
            reject(luvError(e, 'Failed to connect to $to'));
          case Ok(_):
            tcp.noDelay(true);
            final tls = options?.tls;
            if (tls == null) {
              final duplex = new EvalConnection('Connection to $to', tcp);
              app({source: duplex.source, local: duplex.local, peer: duplex.peer})
                .pipeTo(duplex.sink, {end: true})
                .handle(_ -> {});
              resolve(Noise);
            } else {
              switch TlsConfig.fromClient(tls) {
                case Failure(e):
                  Handle.close(tcp, noop);
                  reject(e);
                case Success(tlsCfg):
                  try {
                    final session = new EvalTlsSession(tlsCfg, tcp);
                    session.handshake().handle(o -> switch o {
                      case Success(_):
                        final duplex = new EvalTlsConnection('Connection to $to', session);
                        app({source: duplex.source, local: duplex.local, peer: duplex.peer})
                          .pipeTo(duplex.sink, {end: true})
                          .handle(_ -> {});
                        resolve(Noise);
                      case Failure(e):
                        Handle.close(tcp, noop);
                        reject(e);
                    });
                  } catch (e:haxe.Exception) {
                    Handle.close(tcp, noop);
                    reject(Error.withData(e.message, e));
                  }
              }
            }
        }
      });
      return null;
    });
  }

  static function luvError(e:UVError, message:String):Error {
    return Error.withData('$message: ${e.toString()}', e);
  }

  static function noop() {}
}
#end
