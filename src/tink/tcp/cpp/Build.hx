#if macro
package tink.tcp.cpp;

import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;

class Build {
  /** Injects native/cpp/Build.xml with an absolute path (hxcpp `${this_dir}` is unreliable here). */
  public static function includeNative():Array<Field> {
    final file = Context.getPosInfos(Context.currentPos()).file;
    final srcFile = Context.resolvePath(file);
    // src/tink/tcp/cpp/mbedtls/NativeTls.hx -> native/cpp/Build.xml
    final nativeBuild = sys.FileSystem.absolutePath(
      Path.normalize(Path.join([Path.directory(srcFile), '../../../../../native/cpp/Build.xml']))
    );
    if (!sys.FileSystem.exists(nativeBuild))
      Context.error('tink_tcp native Build.xml not found at $nativeBuild (from $srcFile)', Context.currentPos());
    Context.getLocalClass().get().meta.add(':buildXml', [macro $v{'<include name="$nativeBuild"/>'}], Context.currentPos());
    return Context.getBuildFields();
  }
}
#end
