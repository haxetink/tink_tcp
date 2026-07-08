package tink.tcp;

package tink.tcp;

typedef TlsClientOptions = {
  final ?ca:Bytes;
  final ?cert:Bytes;
  final ?key:Bytes;
  final ?servername:String;
  final ?rejectUnauthorized:Bool;
  final ?alpn:Array<String>;
};

typedef TlsServerOptions = {
  final cert:Bytes;
  final key:Bytes;
  final ?ca:Bytes;
  final ?requestCert:Bool;
  final ?rejectUnauthorized:Bool;
  final ?alpn:Array<String>;
};