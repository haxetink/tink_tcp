#if eval
package tink.tcp.servers;

import eval.luv.*;
import tink.tcp.Server;
import tink.tcp.Connection;
import tink.tcp.connections.EvalConnection;
import tink.tcp.connections.EvalTlsConnection;
import tink.tcp.eval.EvalLoop;
import tink.tcp.tls.TlsConfig;
import tink.io.eval.EvalTlsSession;

using tink.CoreApi;
using eval.luv.Stream;

class EvalServer implements ServerObject {
  final native:Tcp;
  final loop:Loop;
  final trigger:SignalTrigger<Connection>;
  final tls:Null<TlsConfig>;

  public final connected:Signal<Connection>;

  public var port(get, never):Int;

  function get_port() {
    switch native.getSockName() {
      case Ok(addr): return addr.port ?? 0;
      case Error(_): return 0;
    }
  }

  function new(server:Tcp, loop:Loop, trigger:SignalTrigger<Connection>, ?tls:TlsConfig) {
    this.native = server;
    this.loop = loop;
    this.trigger = trigger;
    this.tls = tls;
    this.connected = trigger;
  }

  public function close():Promise<Noise> {
    return new Promise((resolve, reject) -> {
      trigger.clear();
      Handle.close(native, () -> resolve(Noise));
      return null;
    });
  }

  function acceptClient(client:Tcp) {
    client.noDelay(true);
    final name = switch client.getPeerName() {
      case Ok(addr): 'Connection from $addr';
      case Error(_): 'Connection';
    };
    if (tls == null) {
      trigger.trigger((new EvalConnection(name, client) : Connection));
      return;
    }
    try {
      final session = new EvalTlsSession(tls, client);
      session.handshake().handle(o -> switch o {
        case Success(_):
          trigger.trigger((new EvalTlsConnection(name, session) : Connection));
        case Failure(_):
          Handle.close(client, noop);
      });
    } catch (_:haxe.Exception) {
      Handle.close(client, noop);
    }
  }

  static public function bind(target:Endpoint, ?options:BindOptions):Promise<Server> {
    final l = options?.loop ?? EvalLoop.current();
    final tls:Null<TlsConfig> = switch options?.tls {
      case null: null;
      case opts:
        try {
          final cfg:TlsConfig = opts;
          cfg;
        } catch (e:haxe.Exception)
          return Future.sync(Failure(Error.withData(e.message, e)));
    };
    return new Promise((resolve, reject) -> {
      final server = switch Tcp.init(l) {
        case Error(e):
          reject(luvError(e, 'Failed to init TCP server'));
          return null;
        case Ok(v): v;
      };

      final addr = switch SockAddr.ipv4(target.host, target.port) {
        case Error(e):
          Handle.close(server, noop);
          reject(luvError(e, 'Failed to parse bind address for $target'));
          return null;
        case Ok(v): v;
      };

      switch server.bind(addr) {
        case Error(e):
          Handle.close(server, noop);
          reject(luvError(e, 'Failed to bind server on $target'));
          return null;
        case Ok(_):
      }

      final instance = new EvalServer(server, l, Signal.trigger(), tls);
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
                instance.acceptClient(client);
            }
        }
      });

      resolve((instance : Server));
      return null;
    });
  }

  static function luvError(e:UVError, message:String):Error {
    return Error.withData('$message: ${e.toString()}', e);
  }

  static function noop() {}
}
#end
