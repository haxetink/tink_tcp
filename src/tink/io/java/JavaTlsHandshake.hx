#if java
package tink.io.java;

import java.nio.channels.AsynchronousSocketChannel;

using tink.CoreApi;

class JavaTlsHandshake {
  public static function handshake(channel:AsynchronousSocketChannel, engine:java.javax.net.ssl.SSLEngine):Promise<JavaTlsSession> {
    final session = new JavaTlsSession(channel, engine);
    return session.handshake().map(_ -> session);
  }
}
#end
