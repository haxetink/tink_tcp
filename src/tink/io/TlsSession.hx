package tink.io;

using tink.CoreApi;

/**
 * TLS session over TcpSession: adds handshake only.
 * Promise read/write/end are inherited from DuplexStream via TcpSession
 * (platform *TlsSession classes adopt that shape in later chunks).
 */
interface TlsSession extends TcpSession {
  function handshake():Promise<Noise>;
}
