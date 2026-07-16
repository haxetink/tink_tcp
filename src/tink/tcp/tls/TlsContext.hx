package tink.tcp.tls;

#if cpp
typedef TlsContext = tink.tcp.cpp.mbedtls.NativeTls.TlsSslPtr;
#elseif eval
typedef TlsContext = mbedtls.Ssl;
#elseif hl
typedef TlsContext = sys.ssl.Context;
#elseif jvm
typedef TlsContext = java.javax.net.ssl.SSLEngine;
#else
#error 'Unsupported target'
#end