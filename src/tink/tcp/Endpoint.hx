package tink.tcp;

typedef EndpointData = {
  public var host(default, null):String;
	public var port(default, null):Int;
}

@:forward
abstract Endpoint(EndpointData) from EndpointData {
  @:from static function fromPort(port:Int):Endpoint
    return { port: port, host: 'localhost' };
  
  @:to function toString():String
  return '${this.host}:${this.port}';
}