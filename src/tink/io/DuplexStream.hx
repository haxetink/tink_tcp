package tink.io;

import tink.Chunk;

using tink.CoreApi;

interface DuplexStream {
  function read():Promise<Null<Chunk>>;
  function write(chunk:Chunk):Promise<Bool>;
  function end():Promise<Bool>;
}
