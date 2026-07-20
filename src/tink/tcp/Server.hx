package tink.tcp;

import tink.tcp.Tls.TlsServerOptions;

using tink.CoreApi;

typedef BindOptions = {
  ?tls:TlsServerOptions,
  #if eval
  ?loop:eval.luv.Loop,
  #elseif hl
  ?loop:hl.uv.Loop,
  #end
};

@:forward
abstract Server(ServerObject) from ServerObject {
  static public function bind(to:Endpoint, app:Handler, ?options:BindOptions):Promise<Server> {
    #if java
    return tink.tcp.servers.JavaServer.bind(to, app, options);
    #elseif nodejs
    return tink.tcp.servers.NodeServer.bind(to, app, options);
    #elseif eval
    return tink.tcp.servers.EvalServer.bind(to, app, options);
    #elseif hl
    return tink.tcp.servers.HlServer.bind(to, app, options);
    #elseif cpp
    return tink.tcp.servers.CppServer.bind(to, app, options);
    #else
    return Future.sync(Failure(new Error('Not implemented on current platform')));
    #end
  }
}

interface ServerObject {
  var endpoint(get, never):Endpoint;
  function shutdown():Promise<Noise>;
}
