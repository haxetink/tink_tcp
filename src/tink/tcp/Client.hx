package tink.tcp;

import tink.tcp.Tls.TlsClientOptions;

using tink.CoreApi;

typedef ConnectOptions = {
  ?tls:TlsClientOptions,
};

class Client {
  private function new() {}

  static public function connect(to:Endpoint, app:Handler, ?options:ConnectOptions):Promise<Noise> {
    #if java
    return tink.tcp.clients.JavaClient.connect(to, app, options);
    #elseif nodejs
    return tink.tcp.clients.NodeClient.connect(to, app, options);
    #elseif eval
    return tink.tcp.clients.EvalClient.connect(to, app, options);
    #elseif hl
    return tink.tcp.clients.HlClient.connect(to, app, options);
    #elseif cpp
    return tink.tcp.clients.CppClient.connect(to, app, options);
    #else
    return Future.sync(Failure(new Error('Not implemented on current platform')));
    #end
  }
}
