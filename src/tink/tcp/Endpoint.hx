package tink.tcp;

private typedef EndpointData = {
  public var host(default, null):String;
  public var port(default, null):Int;
  @:optional 
  public var secure(default, null):Bool;
}

@:forward(host, port)
abstract Endpoint(EndpointData) from EndpointData {
  public var secure(get, never): Bool;
  function get_secure()
    return 
      if (this.secure == null)
        this.port == 443
      else
        this.secure;
  
  @:from static function fromPort(port:Int):Endpoint
    return { port: port, host: '127.0.0.1' };
  
  @:to public function toString():String
    return '${this.host}:${this.port}';
}