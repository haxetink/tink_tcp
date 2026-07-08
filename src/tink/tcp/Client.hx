package tink.tcp;

import tink.tcp.Tls.TlsClientOptions;

using tink.CoreApi;

typedef ConnectOptions = {
  ?tls:TlsClientOptions,
};

interface Client {
  function connect(to:Endpoint, ?options:ConnectOptions):Promise<Connection>;
}