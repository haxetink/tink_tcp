package tink.tcp.std;

import sys.net.*;
import tink.io.Worker;
import tink.streams.Stream.Handled;

using tink.io.Sink;
using tink.io.Source;
using tink.CoreApi;

class StdConnector {
  static public function connect(to:Endpoint, handler:Handler, ?worker:Worker):Promise<Noise> {
    return Future.async(function(cb) {
      worker = worker.ensure();
      
      var socket = 
        if(to.secure)
          #if php new php.net.SslSocket();
          #elseif java new java.net.SslSocket();
          #elseif (!no_ssl && (hxssl || hl || cpp || (neko && !(macro || interp)))) new sys.ssl.Socket();
          #else throw "Https is only supported with -lib hxssl";
          #end
        else
          new Socket();
          
      var connected:Promise<Noise> = worker.work(function()
        return try {
          socket.connect(new Host(to.host), to.port);
          #if !concurrent socket.setBlocking(false); #end
          Success(Noise);
        } catch(e:Dynamic) Failure(Error.withData('Cannot connect to $to', e))
      );
      
      return connected.next(function(_) {
        var peer = socket.peer();
        var peer:Endpoint = {host: peer.host.toString(), port: peer.port};
        var local = socket.host();
        var local:Endpoint = {host: local.host.toString(), port: local.port};
        var out = 'Outgoing stream of connection to $peer';
        var source = Source.ofInput('Incoming stream of connection to $peer', socket.input);
        var sink = Sink.ofOutput(out, socket.output);
        var sourceClosed = Future.async(function(cb) source.chunked().forEach(function(_) return Resume).handle(function(_) cb(Noise)), true);
        
        return handler.handle({
          stream: source,
          from: peer,
          to: local,
          closed: sourceClosed,
        }).map(function(outgoing) {
          outgoing.stream.pipeTo(sink).handle(function (o) {
            (
              if (outgoing.allowHalfOpen) sourceClosed
              else Future.sync(Noise)
            ).handle(function () {
              try socket.close() catch(e:Dynamic) {}
              cb(switch o {
                case SinkFailed(e, _): Failure(e);
                case SinkEnded(_, { depleted: false }): Failure(new Error('$out closed before all data could be written'));
                default: Success(Noise);
              });
            });
          });
        });
      });
    });
  }
}