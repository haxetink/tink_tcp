#if cpp
package tink.tcp.servers;

import cpp.Callable;
import cpp.Star;
import sys.net.Host;
import tink.tcp.Server;
import tink.tcp.connections.CppConnection;
import tink.tcp.connections.CppTlsConnection;
import tink.tcp.tls.TlsConfig;
import tink.io.Source;
import tink.io.Sink;
import tink.io.cpp.CppTlsSession;
import uv.*;
import uv.Native.UvStream;

using tink.CoreApi;
using tink.io.Source;

class CppServer implements ServerObject {
  final native:Tcp;
  final loop:Loop;
  final app:Handler;
  final tls:Null<TlsConfig>;
  final boundPort:Int;
  final boundHost:String;
  var closeResolve:Null<Noise->Void>;

  public var endpoint(get, never):Endpoint;

  function get_endpoint()
    return {host: boundHost, port: boundPort};

  function new(server:Tcp, loop:Loop, app:Handler, boundHost:String, boundPort:Int, ?tls:TlsConfig) {
    this.native = server;
    this.loop = loop;
    this.app = app;
    this.tls = tls;
    this.boundHost = boundHost;
    this.boundPort = boundPort;
    server.asHandle().setData(this);
  }

  public function shutdown():Promise<Noise> {
    return new Promise((resolve, reject) -> {
      final h = native.asHandle();
      if (h.isClosing()) {
        resolve(Noise);
        return null;
      }
      closeResolve = resolve;
      h.close(Callable.fromStaticFunction(onServerClose));
      return null;
    });
  }

  @:unreflective
  static function onServerClose(handle:Star<uv.Native.UvHandle>) {
    final h:Handle = Native.handle(handle);
    final self:CppServer = h.getData();
    if (self != null && self.closeResolve != null) {
      final cb = self.closeResolve;
      self.closeResolve = null;
      cb(Noise);
    }
  }

  function start(source:RealSource, sink:RealSink, local:Endpoint, peer:Endpoint) {
    app({source: source, local: local, peer: peer})
      .pipeTo(sink, {end: true})
      .handle(_ -> {});
  }

  function acceptClient(client:Tcp) {
    client.nodelay(true);
    final peer = client.getPeerAddress();
    final name = 'Connection from ${peer.host}:${peer.port}';
    final local:Endpoint = {host: boundHost, port: boundPort};
    final peerEp:Endpoint = {host: peer.host, port: peer.port};
    if (tls == null) {
      final duplex = new CppConnection(name, client, local, peerEp);
      start(duplex.source, duplex.sink, duplex.local, duplex.peer);
      return;
    }
    try {
      final session = new CppTlsSession(tls, client);
      session.handshake().handle(o -> switch o {
        case Success(_):
          final duplex = new CppTlsConnection(name, session, local, peerEp);
          start(duplex.source, duplex.sink, duplex.local, duplex.peer);
        case Failure(_):
          closeTcp(client);
      });
    } catch (_:haxe.Exception) {
      closeTcp(client);
    }
  }

  static function uvLoop():Loop {
    #if target.threaded
    final events = haxe.EventLoop.getThreadLoop(sys.thread.Thread.current());
    return Loop.getFromEventLoop(events != null ? events : haxe.EventLoop.main);
    #else
    return Loop.getFromEventLoop(haxe.EventLoop.main);
    #end
  }

  static public function bind(to:Endpoint, app:Handler, ?options:BindOptions):Promise<Server> {
    final l = uvLoop();
    final tls:Null<TlsConfig> = switch options?.tls {
      case null: null;
      case opts:
        switch TlsConfig.fromServer(opts) {
          case Failure(e): return Future.sync(Failure(e));
          case Success(cfg): cfg;
        }
    };

    return new Promise((resolve, reject) -> {
      final hostName = to.host == '0' || to.host == '' ? '0.0.0.0' : to.host;
      var bindHost = hostName;
      try {
        final resolved = new Host(hostName);
        bindHost = resolved.toString();
      } catch (_:Dynamic) {}

      final addr = new SockAddrIn();
      final addrStatus = addr.ip4Addr(bindHost, to.port);
      if (addrStatus != 0) {
        reject(uvError(addrStatus, 'Failed to parse bind address for $to'));
        return null;
      }

      final server = new Tcp();
      final initStatus = server.init(l);
      if (initStatus != 0) {
        reject(uvError(initStatus, 'Failed to init TCP server'));
        return null;
      }

      final bindStatus = server.bind(addr, 0);
      if (bindStatus != 0) {
        closeTcp(server);
        reject(uvError(bindStatus, 'Failed to bind server on $to'));
        return null;
      }

      final sock = server.getSockAddress();
      final instance = new CppServer(server, l, app, sock.host, sock.port, tls);
      final listenStatus = server.asStream().listen(128, Callable.fromStaticFunction(onConnection));
      if (listenStatus != 0) {
        closeTcp(server);
        reject(uvError(listenStatus, 'Failed to listen on $to'));
        return null;
      }

      resolve((instance : Server));
      return null;
    });
  }

  @:unreflective
  static function onConnection(stream:Star<UvStream>, status:Int) {
    if (status != 0)
      return;
    final serverStream:Stream = Native.stream(stream);
    final self:CppServer = serverStream.asHandle().getData();
    if (self == null)
      return;

    final client = new Tcp();
    if (client.init(self.loop) != 0)
      return;
    if (serverStream.accept(client.asStream()) != 0) {
      closeTcp(client);
      return;
    }
    self.acceptClient(client);
  }

  static function closeTcp(tcp:Tcp) {
    final h = tcp.asHandle();
    if (!h.isClosing())
      h.close(Callable.fromStaticFunction(noopClose));
  }

  @:unreflective
  static function noopClose(_:Star<uv.Native.UvHandle>) {}

  static function uvError(code:Int, message:String):Error {
    return Error.withData('$message: ${Std.string(Uv.err_name(code))}', code);
  }
}
#end
