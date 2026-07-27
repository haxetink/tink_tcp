#if hl
package tink.tcp.servers;

import hl.uv.Loop;
import hl.uv.Tcp;
import sys.net.Host;
import tink.tcp.Server;
import tink.tcp.connections.TcpConnection;
import tink.tcp.internal.hl.HlLoop;
import tink.tcp.tls.TlsConfig;
import tink.tcp.internal.hl.HlTlsSession;
import tink.tcp.internal.hl.HlTcpSession;

using tink.CoreApi;

class HlServer implements ServerObject {
  final native:Tcp;
  final loop:Loop;
  final app:Handler;
  final tls:Null<TlsConfig>;
  final boundPort:Int;
  final boundHost:String;
  final errorsTrigger:SignalTrigger<Error> = Signal.trigger();
  var shuttingDown = false;

  public var endpoint(get, never):Endpoint;
  public var errors(get, never):Signal<Error>;

  function get_endpoint()
    return {host: boundHost, port: boundPort};

  function get_errors()
    return errorsTrigger;

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
      shuttingDown = true;
      native.close(() -> resolve(Noise));
      return null;
    });
  }

  function acceptClient(client:hl.uv.Stream) {
    final name = 'Connection';
    final local:Endpoint = {host: boundHost, port: boundPort};
    if (tls == null) {
      final io = new HlTcpSession(name, client, 0x10000, local);
      final duplex = new TcpConnection(name, io);
      app.run(duplex);
      return;
    }
    try {
      final session = new HlTlsSession(tls, client, local);
      session.handshake().handle(o -> switch o {
        case Success(_):
          final duplex = new TcpConnection(name, session);
          app.run(duplex);
        case Failure(e):
          // Handshake failed after accept; peer never reaches Handler.
          errorsTrigger.trigger(e);
          client.close();
      });
    } catch (e:haxe.Exception) {
      errorsTrigger.trigger(Error.withData('TLS session setup failed: ${e.message}', e));
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
        // hl.uv.Stream.listen callback is Void->Void (no UV status). Accept failures
        // surface as throws from Tcp.accept() (typically haxe.io.Eof when handle is
        // null / accept fails). Heuristic: silence when shuttingDown (shutdown closed
        // the listen socket mid-accept); emit all other accept throws on errors.
        server.listen(128, () -> {
          try {
            final client = server.accept();
            instance.acceptClient(client);
          } catch (e:Dynamic) {
            if (!instance.shuttingDown)
              instance.errorsTrigger.trigger(Error.withData('Accept failed: $e', e));
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
