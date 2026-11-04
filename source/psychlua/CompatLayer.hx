package psychlua;

#if LUA_ALLOWED
import sys.FileSystem;
import sys.io.File;

/**
 * Layer di compatibilita' Psych 0.6.3 -> 1.0.x.
 * Il codice Lua e' compilato dentro l'eseguibile (source/psychlua/compat_063.lua),
 * quindi non serve piu' nessun file in mods/scripts/.
 *
 * Override opzionale: se esiste mods/<mod>/scripts/_compatibility_wrapper.lua (o mods/scripts/...),
 * viene eseguito DOPO quello integrato, cosi' una mod puo' aggiungere regole sue.
 */
class CompatLayer
{
	static inline var EXTERNAL_FILE:String = 'scripts/_compatibility_wrapper.lua';
	static final EMBEDDED:String = CompatEmbed.file('psychlua/compat_063.lua');

	/** Ritorna true se il layer e' stato applicato senza errori. */
	public static function inject(funk:FunkinLua):Bool
	{
		var ok:Bool = run(funk, EMBEDDED, 'embedded');

		#if (sys && MODS_ALLOWED)
		var ext:Null<String> = findExternal();
		if (ext != null)
			ok = run(funk, File.getContent(ext), ext) && ok;
		#end
		return ok;
	}

	static function run(funk:FunkinLua, code:String, label:String):Bool
	{
		try
		{
			var result:Dynamic = LuaL.dostring(funk.lua, code);
			if (result != 0)
			{
				var err:String = Lua.tostring(funk.lua, -1);
				Lua.pop(funk.lua, 1);
				// luaTrace cosi' l'errore si vede anche in gioco, non solo nel log
				FunkinLua.luaTrace('[compat] errore ($label) in "${funk.scriptName}": $err', false, false, FlxColor.ORANGE);
				return false;
			}
			return true;
		}
		catch (e:Dynamic)
		{
			trace('[compat] eccezione ($label): $e');
			return false;
		}
	}

	#if (sys && MODS_ALLOWED)
	static function findExternal():Null<String>
	{
		var candidates:Array<String> = [];
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			candidates.push(Paths.mods(Mods.currentModDirectory + '/' + EXTERNAL_FILE));
		candidates.push(Paths.mods(EXTERNAL_FILE));
		for (path in candidates)
			if (FileSystem.exists(path))
				return path;
		return null;
	}
	#end
}
#end
