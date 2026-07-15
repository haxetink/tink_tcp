package tink.io;

import tink.Chunk;

using tink.CoreApi;

interface TlsSession {
  function handshake():Promise<Noise>;
  function read(cb:Callback<Outcome<Null<Chunk>, Error>>):Void;
  function write(chunk:Chunk, cb:Callback<Outcome<Noise, Error>>):Void;
  function shutdown(cb:Callback<Outcome<Noise, Error>>):Void;
}
