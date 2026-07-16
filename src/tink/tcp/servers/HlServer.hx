#if hl
package tink.tcp.servers;

import hl.uv.Loop;
import hl.uv.Tcp;
import sys.net.Host;
import tink.tcp.Server;
import tink.tcp.Connection;
import tink.tcp.connections.HlConnection;
import tink.tcp.connections.HlTlsConnection;
import tink.tcp.hl.HlLoop;
import tink.tcp.tls.TlsConfig;
import tink.io.hl.HlTlsSession;

using tink.CoreApi;

class HlServer implements ServerObject {
  final native:Tcp;
  final loop:Loop;
  final trigger:SignalTrigger<Connection>;
  final tls:Null<TlsConfig>;
  final boundPort:Int;
  final boundHost:String;

  public final connected:Signal<Connection>;

  public var port(get, never):Int;

  function get_port()
    return boundPort;

  function new(server:Tcp, loop:Loop, trigger:SignalTrigger<Connection>, boundHost:String, boundPort:Int, ?tls:TlsConfig) {
    this.native = server;
    this.loop = loop;
    this.trigger = trigger;
    this.tls = tls;
    this.boundHost = boundHost;
    this.boundPort = boundPort;
    this.connected = trigger;
  }

  public function close():Promise<Noise> {
    return new Promise((resolve, reject) -> {
      trigger.clear();
      native.close(() -> resolve(Noise));
      return null;
    });
  }

  function acceptClient(client:hl.uv.Stream) {
    final name = 'Connection';
    final local:Endpoint = {host: boundHost, port: boundPort};
    if (tls == null) {
      trigger.trigger((new HlConnection(name, client, local) : Connection));
      return;
    }
    try {
      final session = new HlTlsSession(tls, client);
      session.handshake().handle(o -> switch o {
        case Success(_):
          trigger.trigger((new HlTlsConnection(name, session, local) : Connection));
        case Failure(_):
          client.close();
      });
    } catch (_:haxe.Exception) {
      client.close();
    }
  }

  static public function bind(target:Endpoint, ?options:BindOptions):Promise<Server> {
    final l = options?.loop ?? HlLoop.current();
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
      final hostName = target.host;
      var port = target.port;
      // hl.uv.Tcp has no getsockname; probe an ephemeral port when binding to 0.
      if (port == 0) {
        try {
          final probe = new sys.net.Socket();
          probe.bind(new Host(hostName), 0);
          port = probe.host().port;
          probe.close();
        } catch (e:Dynamic) {
          reject(new Error('Failed to allocate ephemeral port for $target: $e'));
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

      final instance = new HlServer(server, l, Signal.trigger(), hostName, port, tls);
      try {
        server.listen(128, () -> {
          try {
            final client = server.accept();
            instance.acceptClient(client);
          } catch (_:Dynamic) {
            // drop failed accepts
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
