#if cpp
package tink.tcp.clients;

import cpp.Callable;
import cpp.Star;
import sys.net.Host;
import tink.tcp.Client.ConnectOptions;
import tink.tcp.connections.CppDuplex;
import tink.tcp.connections.CppTlsDuplex;
import tink.tcp.tls.TlsConfig;
import tink.io.cpp.CppTlsSession;
import uv.*;
import uv.Native.UvConnect;

using tink.CoreApi;

private typedef ConnectCtx = {
  tcp:Tcp,
  to:Endpoint,
  options:Null<ConnectOptions>,
  app:Handler,
  resolve:Noise->Void,
  reject:Error->Void,
  connectReq:Connect,
  done:Bool,
};

class CppClient {
  private function new() {}

  static function uvLoop():Loop {
    #if target.threaded
    final events = haxe.EventLoop.getThreadLoop(sys.thread.Thread.current());
    return Loop.getFromEventLoop(events != null ? events : haxe.EventLoop.main);
    #else
    return Loop.getFromEventLoop(haxe.EventLoop.main);
    #end
  }

  static public function connect(to:Endpoint, app:Handler, ?options:ConnectOptions):Promise<Noise> {
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
      final initStatus = tcp.init(uvLoop());
      if (initStatus != 0) {
        reject(uvError(initStatus, 'Failed to init TCP client'));
        return null;
      }

      final connectReq = new Connect();
      final ctx:ConnectCtx = {
        tcp: tcp,
        to: to,
        options: options,
        app: app,
        resolve: resolve,
        reject: reject,
        connectReq: connectReq,
        done: false,
      };
      connectReq.setData(ctx);
      final status = tcp.connect(connectReq, dest, Callable.fromStaticFunction(onConnect));
      if (status != 0) {
        finish(ctx, () -> {
          closeTcp(tcp);
          reject(uvError(status, 'Failed to connect to $to'));
        });
        return null;
      }
      return () -> if (!ctx.done) {
        ctx.done = true;
        closeTcp(tcp);
      };
    });
  }

  static function finish(ctx:ConnectCtx, f:Void->Void) {
    if (!ctx.done) {
      ctx.done = true;
      f();
    }
  }

  @:unreflective
  static function onConnect(req:Star<UvConnect>, status:Int) {
    final connectReq:Connect = Native.connect(req);
    final ctx:ConnectCtx = connectReq.getData();
    if (status != 0) {
      // Close inside finish so cancel (which already closed) cannot double-close.
      finish(ctx, () -> {
        closeTcp(ctx.tcp);
        ctx.reject(uvError(status, 'Failed to connect to ${ctx.to}'));
      });
      return;
    }
    if (ctx.done)
      return;
    ctx.tcp.nodelay(true);
    final tls = ctx.options?.tls;
    if (tls == null) {
      finish(ctx, () -> {
        final duplex = new CppDuplex('Connection to ${ctx.to}', ctx.tcp);
        Session.run(duplex.source, duplex.sink, duplex.local, duplex.peer, ctx.app, duplex.abort);
        ctx.resolve(Noise);
      });
      return;
    }
    switch TlsConfig.fromClient(tls) {
      case Failure(e):
        finish(ctx, () -> {
          closeTcp(ctx.tcp);
          ctx.reject(e);
        });
      case Success(tlsCfg):
        try {
          final session = new CppTlsSession(tlsCfg, ctx.tcp);
          session.handshake().handle(o -> switch o {
            case Success(_):
              finish(ctx, () -> {
                final duplex = new CppTlsDuplex('Connection to ${ctx.to}', session, null, ctx.to);
                Session.run(duplex.source, duplex.sink, duplex.local, duplex.peer, ctx.app, duplex.abort);
                ctx.resolve(Noise);
              });
            case Failure(e):
              finish(ctx, () -> {
                closeTcp(ctx.tcp);
                ctx.reject(e);
              });
          });
        } catch (e:haxe.Exception) {
          finish(ctx, () -> {
            closeTcp(ctx.tcp);
            ctx.reject(Error.withData(e.message, e));
          });
        }
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
