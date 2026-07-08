#if eval
package tink.tcp.clients;

import eval.luv.*;
import tink.tcp.Client;
import tink.tcp.Connection;
import tink.tcp.connections.EvalConnection;

using tink.CoreApi;

class EvalClient implements Client {
  final loop:Loop;

  public function new(?loop:Loop) {
    this.loop = loop ?? (sys.thread.Thread.current().events : Loop);
  }

  public function connect(to:Endpoint):Promise<Connection> {
    if (to.secure)
      return new Error('TLS is not supported on eval target');

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
            resolve((new EvalConnection('Connection to $to', tcp) : Connection));
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