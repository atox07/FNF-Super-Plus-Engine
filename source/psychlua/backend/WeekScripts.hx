package psychlua.backend;

import backend.WeekData;

/**
 * Esegue gli script dei modder che decidono quali week mostrare.
 *
 *   mods/<Mod>/scripts/weeks/init.lua   (oppure init.hx)
 *
 *   function onLoadWeeks(isStoryMode)   -- true = Story, false = Freeplay, nil = editor
 *       hideBaseWeeks()                 -- nasconde tutte le week del gioco base
 *       hideWeek('week1')               -- nasconde una singola week (anche di altre mod)
 *   end
 *
 * Le funzioni hideBaseWeeks() / hideWeek() esistono solo durante onLoadWeeks.
 * Chiamato da WeekData.reloadWeekFiles prima della scansione delle cartelle.
 */
class WeekScripts
{
	public static inline var FOLDER:String = 'scripts/weeks';

	public static function run(isStoryMode:Null<Bool>):Void
	{
		#if ((LUA_ALLOWED || HSCRIPT_ALLOWED) && MODS_ALLOWED)
		var host:flixel.FlxState = MusicBeatState.getState();
		if (host == null)
			return;

		var args:Array<Dynamic> = [isStoryMode];
		for (mod in modsToRun())
		{
			var scripts:MenuScripts = null;
			try
			{
				// Se lo script non esiste non crea nulla (solo un paio di FileSystem.exists)
				scripts = new MenuScripts(host, FOLDER, mod);
				bind(scripts);
				scripts.call('onLoadWeeks', args);
			}
			catch (e:Dynamic)
			{
				// Errore nello script = non nasconde niente, il menu non si rompe
				trace('[WeekScripts] "$mod": $e');
			}

			if (scripts != null)
				scripts.destroy();
		}
		#end
	}

	#if ((LUA_ALLOWED || HSCRIPT_ALLOWED) && MODS_ALLOWED)
	static function modsToRun():Array<String>
	{
		var list:Array<String> = [];
		if (Mods.launchedMod != null && Mods.launchedMod.length > 0)
		{
			// Contesto isolato: conta solo la mod lanciata
			if (!backend.ModSecurity.isBlocked(Mods.launchedMod))
				list.push(Mods.launchedMod);
		}
		else
		{
			for (mod in Mods.parseList().enabled)
				if (!Mods.isBaseGameMod(mod) && !backend.ModSecurity.isBlocked(mod))
					list.push(mod);
		}
		return list;
	}

	static function hideBase():Void
		WeekData.baseWeeksDisabled = true;

	static function hideWeek(name:String):Void
	{
		if (name != null && name.length > 0 && !WeekData.hiddenWeeks.contains(name))
			WeekData.hiddenWeeks.push(name);
	}

	static function bind(scripts:MenuScripts):Void
	{
		#if LUA_ALLOWED
		for (script in scripts.luaArray)
		{
			if (script == null || script.lua == null)
				continue;
			script.addLocalCallback('hideBaseWeeks', function() hideBase());
			script.addLocalCallback('hideWeek', function(name:String) hideWeek(name));
		}
		#end

		#if HSCRIPT_ALLOWED
		for (script in scripts.hscriptArray)
		{
			if (script == null)
				continue;
			script.set('hideBaseWeeks', function() hideBase());
			script.set('hideWeek', function(name:String) hideWeek(name));
		}
		#end
	}
	#end
}
