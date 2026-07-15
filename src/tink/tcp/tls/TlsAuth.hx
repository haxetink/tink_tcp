package tink.tcp.tls;

import tink.tcp.Tls.TlsClientOptions;
import tink.tcp.Tls.TlsServerOptions;

enum TlsAuthMode {
  None;
  Optional;
  Required;
}

class TlsAuth {
  public static function clientMode(opts:TlsClientOptions):TlsAuthMode {
    if (opts.rejectUnauthorized == false)
      return None;
    if (opts.ca != null)
      return Required;
    return None;
  }

  public static function serverMode(opts:TlsServerOptions):TlsAuthMode {
    if (opts.requestCert == true)
      return opts.rejectUnauthorized == true ? Required : Optional;
    if (opts.rejectUnauthorized == true)
      return Optional;
    return None;
  }
}
