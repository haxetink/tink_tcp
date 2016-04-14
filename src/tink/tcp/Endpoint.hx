package tink.tcp;

private typedef EndpointData = {
  public var host(default, null):String;
  public var port(default, null):Int;
}

@:forward
abstract Endpoint(EndpointData) from EndpointData {
  @:from static function fromPort(port:Int):Endpoint
    return { port: port, host: '127.0.0.1' };
  
  @:to function toString():String
    return '${this.host}:${this.port}';
}