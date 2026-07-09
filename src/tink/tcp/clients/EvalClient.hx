#if eval
package tink.tcp.clients;

import eval.luv.*;
import tink.tcp.Client;
import tink.tcp.Client.ConnectOptions;
import tink.tcp.Connection;
import tink.tcp.connections.EvalConnection;
import tink.tcp.connections.EvalTlsConnection;
import tink.tcp.eval.EvalLoop;
import tink.tcp.tls.eval.EvalTlsClientConfig;
import tink.io.eval.EvalTlsSession;

using tink.CoreApi;

class EvalClient implements Client {
  final loop:Loop;

  public function new(?loop:Loop) {
    this.loop = loop ?? EvalLoop.current();
  }

  public function connect(to:Endpoint, ?options:ConnectOptions):Promise<Connection> {
    final addr = switch SockAddr.ipv4(to.host, to.port) {
      case Ok(addr): addr;
      case Error(e):
        return luvError(e, 'Failed to parse address ${to.host}:${to.port}');
    };

    return new Promise((resolve, reject) -> {
      final tcp = switch Tcp.init(loop) {
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
              resolve((new EvalConnection('Connection to $to', tcp) : Connection));
            } else {
              try {
                final cfg:EvalTlsClientConfig = tls;
                final ctx = cfg.createContext();
                final ssl = ctx.newSsl();
                cfg.configureSsl(ssl, ctx);
                final session = new EvalTlsSession(tcp, ssl, ctx);
                session.handshake().handle(o -> switch o {
                  case Success(_):
                    resolve((new EvalTlsConnection('Connection to $to', session) : Connection));
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