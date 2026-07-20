#if eval
package tink.tcp.servers;

import eval.luv.*;
import tink.tcp.Server;
import tink.tcp.connections.EvalConnection;
import tink.tcp.connections.EvalTlsConnection;
import tink.tcp.eval.EvalLoop;
import tink.tcp.tls.TlsConfig;
import tink.io.Source;
import tink.io.Sink;
import tink.io.eval.EvalTlsSession;

using tink.CoreApi;
using eval.luv.Stream;

class EvalServer implements ServerObject {
  final native:Tcp;
  final loop:Loop;
  final app:Handler;
  final tls:Null<TlsConfig>;

  public var endpoint(get, never):Endpoint;

  function get_endpoint() {
    return switch native.getSockName() {
      case Ok(addr): (addr : Endpoint);
      case Error(_): {host: '?', port: 0};
    };
  }

  function new(server:Tcp, loop:Loop, app:Handler, ?tls:TlsConfig) {
    this.native = server;
    this.loop = loop;
    this.app = app;
    this.tls = tls;
  }

  public function shutdown():Promise<Noise> {
    return new Promise((resolve, reject) -> {
      Handle.close(native, () -> resolve(Noise));
      return null;
    });
  }

  function start(source:RealSource, sink:RealSink, local:Endpoint, peer:Endpoint) {
    Session.run(source, sink, local, peer, app);
  }

  function acceptClient(client:Tcp) {
    client.noDelay(true);
    final name = switch client.getPeerName() {
      case Ok(addr): 'Connection from $addr';
      case Error(_): 'Connection';
    };
    if (tls == null) {
      final duplex = new EvalConnection(name, client);
      start(duplex.source, duplex.sink, duplex.local, duplex.peer);
      return;
    }
    try {
      final session = new EvalTlsSession(tls, client);
      session.handshake().handle(o -> switch o {
        case Success(_):
          final duplex = new EvalTlsConnection(name, session);
          start(duplex.source, duplex.sink, duplex.local, duplex.peer);
        case Failure(_):
          Handle.close(client, noop);
      });
    } catch (_:haxe.Exception) {
      Handle.close(client, noop);
    }
  }

  static public function bind(to:Endpoint, app:Handler, ?options:BindOptions):Promise<Server> {
    final l = options?.loop ?? EvalLoop.current();
    final tls:Null<TlsConfig> = switch options?.tls {
      case null: null;
      case opts:
        switch TlsConfig.fromServer(opts) {
          case Failure(e): return Future.sync(Failure(e));
          case Success(cfg): cfg;
        }
    };
    return new Promise((resolve, reject) -> {
      final server = switch Tcp.init(l) {
        case Error(e):
          reject(luvError(e, 'Failed to init TCP server'));
          return null;
        case Ok(v): v;
      };

      final addr = switch SockAddr.ipv4(to.host, to.port) {
        case Error(e):
          Handle.close(server, noop);
          reject(luvError(e, 'Failed to parse bind address for $to'));
          return null;
        case Ok(v): v;
      };

      switch server.bind(addr) {
        case Error(e):
          Handle.close(server, noop);
          reject(luvError(e, 'Failed to bind server on $to'));
          return null;
        case Ok(_):
      }

      final instance = new EvalServer(server, l, app, tls);
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
