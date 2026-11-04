package psychlua;

import haxe.macro.Context;
import haxe.macro.Expr;

/**
 * Incorpora un file di testo nel binario a tempo di compilazione.
 * Il path viene cercato nei classpath (quindi "psychlua/compat_063.lua" -> source/psychlua/compat_063.lua).
 */
class CompatEmbed
{
	public static macro function file(path:String):Expr
	{
		var full:String = Context.resolvePath(path);
		return macro $v{sys.io.File.getContent(full)};
	}
}
