package tink.io;

import tink.tcp.Endpoint;

/**
 * Connection-facing session over DuplexStream I/O:
 * abort plus local/peer endpoints.
 */
interface TcpSession extends DuplexStream {
  function abort():Void;
  function getLocalEndpoint():Endpoint;
  function getPeerEndpoint():Endpoint;
}
