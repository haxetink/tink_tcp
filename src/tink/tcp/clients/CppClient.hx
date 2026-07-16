#if cpp
package tink.tcp.clients;

import cpp.Callable;
import cpp.Star;
import sys.net.Host;
import tink.tcp.Client;
import tink.tcp.Client.ConnectOptions;
import tink.tcp.Connection;
import tink.tcp.connections.CppConnection;
import tink.tcp.connections.CppTlsConnection;
import tink.tcp.tls.TlsConfig;
import tink.io.cpp.CppTlsSession;
import uv.*;
import uv.Native.UvConnect;

using tink.CoreApi;

private typedef ConnectCtx = {
  client:CppClient,
  tcp:Tcp,
  to:Endpoint,
  options:Null<ConnectOptions>,
  resolve:Connection->Void,
  reject:Error->Void,
  connectReq:Connect,
};

class CppClient implements Client {
  final loop:Loop;

  public function new() {
    this.loop = uvLoop();
  }

  static function uvLoop():Loop {
    #if target.threaded
    final events = haxe.EventLoop.getThreadLoop(sys.thread.Thread.current());
    return Loop.getFromEventLoop(events != null ? events : haxe.EventLoop.main);
    #else
    return Loop.getFromEventLoop(haxe.EventLoop.main);
    #end
  }

  public function connect(to:Endpoint, ?options:ConnectOptions):Promise<Connection> {
    return new Promise((resolve, reject) -> {
      final host = try new Host(to.host) catch (e:Dynamic) {
        reject(new Error('Failed to resolve ${to.host}: $e'));
        return null;
      };
      final ip = host.toString();
      final dest = new SockAddrIn();
      final addrStatus = dest.ip4Addr(ip, to.port);
      if (addrStatus != 0) {
        reject(uvError(addrStatus, 'Failed to parse address $ip:${to.port}'));
        return null;
      }

      final tcp = new Tcp();
      final initStatus = tcp.init(loop);
      if (initStatus != 0) {
        reject(uvError(initStatus, 'Failed to init TCP client'));
        return null;
      }

      final connectReq = new Connect();
      final ctx:ConnectCtx = {
        client: this,
        tcp: tcp,
        to: to,
        options: options,
        resolve: resolve,
        reject: reject,
        connectReq: connectReq,
      };
      connectReq.setData(ctx);
      final status = tcp.connect(connectReq, dest, Callable.fromStaticFunction(onConnect));
      if (status != 0) {
        closeTcp(tcp);
        reject(uvError(status, 'Failed to connect to $to'));
      }
      return null;
    });
  }

  @:unreflective
  static function onConnect(req:Star<UvConnect>, status:Int) {
    final connectReq:Connect = Native.connect(req);
    final ctx:ConnectCtx = connectReq.getData();
    if (status != 0) {
      closeTcp(ctx.tcp);
      ctx.reject(uvError(status, 'Failed to connect to ${ctx.to}'));
      return;
    }
    ctx.tcp.nodelay(true);
    final tls = ctx.options?.tls;
    if (tls == null) {
      ctx.resolve((new CppConnection('Connection to ${ctx.to}', ctx.tcp) : Connection));
      return;
    }
    try {
      final tlsCfg:TlsConfig = tls;
      final session = new CppTlsSession(tlsCfg, ctx.tcp);
      session.handshake().handle(o -> switch o {
        case Success(_):
          ctx.resolve((new CppTlsConnection('Connection to ${ctx.to}', session, null, ctx.to) : Connection));
        case Failure(e):
          closeTcp(ctx.tcp);
          ctx.reject(e);
      });
    } catch (e:haxe.Exception) {
      closeTcp(ctx.tcp);
      ctx.reject(Error.withData(e.message, e));
    }
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
