#if eval
package tink.tcp.servers;

import eval.luv.*;
import tink.tcp.Server;
import tink.tcp.Connection;
import tink.tcp.connections.EvalConnection;

using tink.CoreApi;
using eval.luv.Stream;

class EvalServer implements ServerObject {
  final native:Tcp;
  final loop:Loop;
  final trigger:SignalTrigger<Connection>;

  public final connected:Signal<Connection>;

  public var port(get, never):Int;

  function get_port() {
    switch native.getSockName() {
      case Ok(addr): return addr.port ?? 0;
      case Error(_): return 0;
    }
  }

  function new(server:Tcp, loop:Loop, trigger:SignalTrigger<Connection>) {
    this.native = server;
    this.loop = loop;
    this.trigger = trigger;
    this.connected = trigger;
  }

  public function close():Promise<Noise> {
    return new Promise((resolve, reject) -> {
      trigger.clear();
      Handle.close(native, () -> resolve(Noise));
      return null;
    });
  }

  static public function bind(port:Int, ?loop:Loop):Promise<Server> {
    final l = loop ?? (sys.thread.Thread.current().events : Loop);
    return new Promise((resolve, reject) -> {
      final server = switch Tcp.init(l) {
        case Error(e):
          reject(luvError(e, 'Failed to init TCP server'));
          return null;
        case Ok(v): v;
      };

      final addr = switch SockAddr.ipv4('0.0.0.0', port) {
        case Error(e):
          Handle.close(server, noop);
          reject(luvError(e, 'Failed to parse bind address for port $port'));
          return null;
        case Ok(v): v;
      };

      switch server.bind(addr) {
        case Error(e):
          Handle.close(server, noop);
          reject(luvError(e, 'Failed to bind server on port $port'));
          return null;
        case Ok(_):
      }

      final t = Signal.trigger();
      server.listen(function(result) {
        switch result {
          case Error(e):
            // TODO: report accept errors
          case Ok(_):
            final client = switch Tcp.init(l) {
              case Error(_): return;
              case Ok(v): v;
            };
            switch server.accept(client) {
              case Error(_):
                Handle.close(client, noop);
              case Ok(_):
                client.noDelay(true);
                final name = switch client.getPeerName() {
                  case Ok(addr): 'Connection from $addr';
                  case Error(_): 'Connection';
                };
                t.trigger((new EvalConnection(name, client) : Connection));
            }
        }
      });

      resolve((new EvalServer(server, l, t) : Server));
      return null;
    });
  }

  static function luvError(e:UVError, message:String):Error {
    return Error.withData('$message: ${e.toString()}', e);
  }

  static function noop() {}
}
#end