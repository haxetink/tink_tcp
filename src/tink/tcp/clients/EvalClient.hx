#if eval
package tink.tcp.clients;

import eval.luv.*;
import tink.io.luv.WrappedStream;
import tink.tcp.Client.ConnectOptions;
import tink.tcp.connections.TcpConnection;
import tink.tcp.eval.EvalLoop;
#if eval_tls
import tink.tcp.connections.TlsConnection;
import tink.tcp.tls.TlsConfig;
import tink.io.eval.EvalTlsSession;
#end

using tink.CoreApi;

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
      var done = false;
      function finish(f:Void->Void) {
        if (!done) {
          done = true;
          f();
        }
      }

      final tcp = switch Tcp.init(l) {
        case Error(e):
          reject(luvError(e, 'Failed to init TCP client'));
          return null;
        case Ok(v): v;
      };

      tcp.connect(addr, function(result) {
        switch result {
          case Error(e):
            // Close inside finish so cancel (which already closed) cannot double-close.
            finish(() -> {
              Handle.close(tcp, noop);
              reject(luvError(e, 'Failed to connect to $to'));
            });
          case Ok(_):
            if (done)
              return;
            tcp.noDelay(true);
            #if eval_tls
            final tls = options?.tls;
            if (tls != null) {
              switch TlsConfig.fromClient(tls) {
                case Failure(e):
                  finish(() -> {
                    Handle.close(tcp, noop);
                    reject(e);
                  });
                case Success(tlsCfg):
                  try {
                    final session = new EvalTlsSession(tlsCfg, tcp);
                    session.handshake().handle(o -> switch o {
                      case Success(_):
                        finish(() -> {
                          final duplex = new TlsConnection('Connection to $to', session);
                          app.run(duplex);
                          resolve(Noise);
                        });
                      case Failure(e):
                        finish(() -> {
                          Handle.close(tcp, noop);
                          reject(e);
                        });
                    });
                  } catch (e:haxe.Exception) {
                    finish(() -> {
                      Handle.close(tcp, noop);
                      reject(Error.withData(e.message, e));
                    });
                  }
              }
              return;
            }
            #else
            if (options?.tls != null) {
              finish(() -> {
                Handle.close(tcp, noop);
                reject(new Error('Eval TLS requires -D eval_tls'));
              });
              return;
            }
            #end
            finish(() -> {
              final name = 'Connection to $to';
              final stream = new WrappedStream(name, tcp);
              final duplex = new TcpConnection(name, stream);
              app.run(duplex);
              resolve(Noise);
            });
        }
      });
      return () -> if (!done) {
        done = true;
        Handle.close(tcp, noop);
      };
    });
  }

  static function luvError(e:UVError, message:String):Error {
    return Error.withData('$message: ${e.toString()}', e);
  }

  static function noop() {}
}
#end
