package tink.tcp;

import tink.io.Source;

typedef IncomingConnection = {
  final source:RealSource;
  final local:Endpoint;
  final peer:Endpoint;
}

typedef Handler = IncomingConnection->IdealSource;
