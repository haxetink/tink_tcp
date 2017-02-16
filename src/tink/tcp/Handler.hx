package tink.tcp;

using tink.io.Source;
using tink.CoreApi;

abstract Handler(Ref<Incoming->Future<Outgoing>>) {
  inline function new(f)
    this = Ref.to(f);

  public function handle(incoming:Incoming):Future<Outgoing> 
    return this.value(incoming);
  
  @:from static private function ofAsync(f:Incoming->Future<Outgoing>)
    return new Handler(f);
    
  @:from static private function ofSync(f:Incoming->Outgoing)
    return ofAsync(function (i) return Future.sync(f(i)));
    
}