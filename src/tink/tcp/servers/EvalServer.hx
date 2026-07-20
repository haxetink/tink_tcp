#if eval
package tink.tcp.servers;

import eval.luv.*;
import tink.tcp.Server;
import tink.tcp.connections.EvalDuplex;
import tink.tcp.eval.EvalLoop;
#if eval_tls
import tink.tcp.connections.EvalTlsDuplex;
import tink.tcp.tls.TlsConfig;
import tink.io.eval.EvalTlsSession;
#end

using tink.CoreApi;
using eval.luv.Stream;

class EvalServer implements ServerObject {
  final native:Tcp;
  final loop:Loop;
  final app:Handler;
  #if eval_tls
  final tls:Null<TlsConfig>;
  #end

  public var endpoint(get, never):Endpoint;

  function get_endpoint() {
    return switch native.getSockName() {
      case Ok(addr): (addr : Endpoint);
      case Error(_): {host: '?', port: 0};
    };
  }

  private function new(server:Tcp, loop:Loop, app:Handler #if eval_tls , ?tls:TlsConfig #end) {
    this.native = server;
    this.loop = loop;
    this.app = app;
    #if eval_tls
    this.tls = tls;
    #end
  }

  public function shutdown():Promise<Noise> {
    return new Promise((resolve, reject) -> {
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
    #if eval_tls
    if (tls != null) {
      try {
        final session = new EvalTlsSession(tls, client);
        session.handshake().handle(o -> switch o {
          case Success(_):
            final duplex = new EvalTlsDuplex(name, session);
            Session.run(duplex.source, duplex.sink, duplex.local, duplex.peer, app);
          case Failure(_):
            Handle.close(client, noop);
        });
      } catch (_:haxe.Exception) {
        Handle.close(client, noop);
      }
      return;
    }
    #end
    final duplex = new EvalDuplex(name, client);
    Session.run(duplex.source, duplex.sink, duplex.local, duplex.peer, app);
  }

  static public function bind(to:Endpoint, app:Handler, ?options:BindOptions):Promise<Server> {
    final l = options?.loop ?? EvalLoop.current();
    #if eval_tls
    final tls:Null<TlsConfig> = switch options?.tls {
      case null: null;
      case opts:
        switch TlsConfig.fromServer(opts) {
          case Failure(e): return Future.sync(Failure(e));
          case Success(cfg): cfg;
        }
    };
    #else
    if (options?.tls != null)
      return Future.sync(Failure(new Error('Eval TLS requires -D eval_tls')));
    #end
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

      final instance = new EvalServer(server, l, app #if eval_tls , tls #end);
      server.listen(function(result) {
        switch result {
          case Error(_):
            // Expected when shutdown() closes the listen socket while accept is pending.
            // TODO: report other accept errors
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
