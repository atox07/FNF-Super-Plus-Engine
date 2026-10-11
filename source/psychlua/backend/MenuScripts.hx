package psychlua.backend;

#if LUA_ALLOWED
import psychlua.backend.FunkinLua;
#end
#if HSCRIPT_ALLOWED
import psychlua.backend.HScript;
#end
#if sys
import sys.FileSystem;
#end
import flixel.FlxState;

/**
 * Loader di script indipendente per state diversi da PlayState (per ora: MainMenuState).
 * Carica <folder>/init.lua e <folder>/init.hx, richiama gli hook di lifecycle.
 * Non tocca luaArray/hscriptArray di PlayState né il sistema di companion script
 * (disattivato) in MusicBeatState.
 */
class MenuScripts
{
	#if LUA_ALLOWED
	public var luaArray:Array<FunkinLua> = [];
	#end
	#if HSCRIPT_ALLOWED
	public var hscriptArray:Array<HScript> = [];
	#end

	var host:FlxState;

	public function new(host:FlxState, folder:String)
	{
		this.host = host;
		load(folder);
	}

	function load(folder:String):Void
	{
		#if LUA_ALLOWED
		var luaPath:String = findScript('$folder/init.lua');
		if (luaPath != null)
		{
			var context = new LuaHostContext(LuaHostKind.NONE, luaPath, host, MusicBeatState.getState(), MusicBeatState.getVariables(), luaArray);
			new FunkinLua(luaPath, context); // si auto-registra in luaArray tramite context.scriptList
		}
		#end

		#if HSCRIPT_ALLOWED
		var hxPath:String = findScript('$folder/init.hx');
		if (hxPath != null)
		{
			try
			{
				var script = new HScript(null, hxPath);
				hscriptArray.push(script);
				callOnHScript(script, 'onCreate', []);
			}
			catch (e:Dynamic)
			{
				trace('MenuScripts: failed to load $hxPath: $e');
			}
		}
		#end
	}

	function findScript(rel:String):Null<String>
	{
		#if (MODS_ALLOWED && sys)
		var modded:String = Paths.modFolders(rel);
		if (modded != null && FileSystem.exists(modded))
			return modded;
		#end

		#if sys
		var shared:String = Paths.getSharedPath(rel);
		if (shared != null && FileSystem.exists(shared))
			return shared;
		#end

		return null;
	}

	public function call(func:String, ?args:Array<Dynamic>):Dynamic
	{
		if (args == null)
			args = [];
		var ret:Dynamic = LuaUtils.Function_Continue;

		#if LUA_ALLOWED
		for (script in luaArray)
		{
			if (script == null || script.lua == null)
				continue;
			var r = script.call(func, args);
			if (LuaUtils.isStop(r))
				ret = r;
		}
		#end

		#if HSCRIPT_ALLOWED
		for (script in hscriptArray)
		{
			var r = callOnHScript(script, func, args);
			if (LuaUtils.isStop(r))
				ret = r;
		}
		#end

		return ret;
	}

	#if HSCRIPT_ALLOWED
	function callOnHScript(script:HScript, func:String, args:Array<Dynamic>):Dynamic
	{
		if (script == null || !script.exists(func))
			return LuaUtils.Function_Continue;
		try
		{
			var callValue = script.call(func, args);
			if (callValue != null && callValue.returnValue != null)
				return callValue.returnValue;
		}
		catch (e:Dynamic)
		{
			trace('MenuScripts: error calling $func: $e');
		}
		return LuaUtils.Function_Continue;
	}
	#end

	public function destroy():Void
	{
		#if LUA_ALLOWED
		for (script in luaArray)
			if (script != null)
				script.stop();
		luaArray = [];
		#end

		#if HSCRIPT_ALLOWED
		for (script in hscriptArray)
			if (script != null)
				script.destroy();
		hscriptArray = [];
		#end
	}
}
