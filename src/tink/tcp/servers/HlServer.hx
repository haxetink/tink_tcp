#if hl
package tink.tcp.servers;

import hl.uv.Loop;
import hl.uv.Tcp;
import sys.net.Host;
import tink.tcp.Server;
import tink.tcp.connections.HlDuplex;
import tink.tcp.connections.HlTlsDuplex;
import tink.tcp.hl.HlLoop;
import tink.tcp.tls.TlsConfig;
import tink.io.hl.HlTlsSession;

using tink.CoreApi;

class HlServer implements ServerObject {
  final native:Tcp;
  final loop:Loop;
  final app:Handler;
  final tls:Null<TlsConfig>;
  final boundPort:Int;
  final boundHost:String;

  public var endpoint(get, never):Endpoint;

  function get_endpoint()
    return {host: boundHost, port: boundPort};

  private function new(server:Tcp, loop:Loop, app:Handler, boundHost:String, boundPort:Int, ?tls:TlsConfig) {
    this.native = server;
    this.loop = loop;
    this.app = app;
    this.tls = tls;
    this.boundHost = boundHost;
    this.boundPort = boundPort;
  }

  public function shutdown():Promise<Noise> {
    return new Promise((resolve, reject) -> {
      native.close(() -> resolve(Noise));
      return null;
    });
  }

  function acceptClient(client:hl.uv.Stream) {
    final name = 'Connection';
    final local:Endpoint = {host: boundHost, port: boundPort};
    if (tls == null) {
      final duplex = new HlDuplex(name, client, local);
      Session.run(duplex.source, duplex.sink, duplex.local, duplex.peer, app);
      return;
    }
    try {
      final session = new HlTlsSession(tls, client);
      session.handshake().handle(o -> switch o {
        case Success(_):
          final duplex = new HlTlsDuplex(name, session, local);
          Session.run(duplex.source, duplex.sink, duplex.local, duplex.peer, app);
        case Failure(_):
          // Handshake failed after accept; close peer and keep listening.
          client.close();
      });
    } catch (_:haxe.Exception) {
      client.close();
    }
  }

  static public function bind(to:Endpoint, app:Handler, ?options:BindOptions):Promise<Server> {
    final l = options?.loop ?? HlLoop.current();
    final tls:Null<TlsConfig> = switch options?.tls {
      case null: null;
      case opts:
        switch TlsConfig.fromServer(opts) {
          case Failure(e): return Future.sync(Failure(e));
          case Success(cfg): cfg;
        }
    };

    return new Promise((resolve, reject) -> {
      final hostName = to.host;
      var port = to.port;
      // hl.uv.Tcp has no getsockname; probe an ephemeral port when binding to 0.
      if (port == 0) {
        try {
          final probe = new sys.net.Socket();
          probe.bind(new Host(hostName), 0);
          port = probe.host().port;
          probe.close();
        } catch (e:Dynamic) {
          reject(new Error('Failed to allocate ephemeral port for $to: $e'));
          return null;
        }
      }

      final server = new Tcp(l);
      try {
        server.bind(new Host(hostName), port);
      } catch (e:Dynamic) {
        server.close();
        reject(new Error('Failed to bind server on $hostName:$port: $e'));
        return null;
      }

      final instance = new HlServer(server, l, app, hostName, port, tls);
      try {
        server.listen(128, () -> {
          try {
            final client = server.accept();
            instance.acceptClient(client);
          } catch (_:Dynamic) {
            // Expected when shutdown() closes the listen socket while accept is pending.
            // TODO: report other accept errors
          }
        });
      } catch (e:Dynamic) {
        server.close();
        reject(new Error('Failed to listen on $hostName:$port: $e'));
        return null;
      }

      resolve((instance : Server));
      return null;
    });
  }
}
#end
