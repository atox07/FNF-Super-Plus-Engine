package states.editors.eventcreator;

import backend.Mods;
import backend.Paths;

using StringTools;

/**
 * Liste di scelte per i dropdown dei tipi character / sound / image / stage.
 * Usa lo stesso schema di PlayState: Mods.directoriesWithFile(...) + Paths.readDirectory(...),
 * quindi vede sia gli asset base sia la cartella delle mod attive.
 * Le liste sono in cache: chiama invalidate() se i file cambiano mentre l'editor e' aperto.
 */
class EventPresets
{
	static var cache:Map<String, Array<String>> = new Map();

	/** Oggetti Lua che esistono sempre in PlayState e si possono usare come target dei tween. */
	static final TARGETS:Array<String> = ['boyfriend', 'dad', 'gf'];

	public static function invalidate():Void
		cache = new Map();

	/**
	 * kind: 'character' (boyfriend/dad/gf + file personaggio), 'characterfile' (solo file personaggio),
	 *       'sound', 'image', 'stage'. Restituisce sempre una COPIA.
	 */
	public static function list(kind:String):Array<String>
	{
		var cached:Array<String> = cache.get(kind);
		if (cached != null)
			return cached.copy();

		var out:Array<String> = [];
		switch (kind)
		{
			case 'character':
				out = TARGETS.copy();
				for (n in scan('characters', '.json'))
					if (!out.contains(n))
						out.push(n);
			case 'characterfile':
				out = scan('characters', '.json');
			case 'sound':
				out = scan('sounds', '.' + Paths.SOUND_EXT);
			case 'image':
				out = scan('images', '.png');
			case 'stage':
				out = scan('stages', '.json');
			default:
		}

		cache.set(kind, out);
		return out.copy();
	}

	/** Nomi dei file (senza estensione) direttamente dentro <folder>/ in assets/shared e nei mod. */
	static function scan(folder:String, ext:String):Array<String>
	{
		var out:Array<String> = [];
		try
		{
			for (dir in Mods.directoriesWithFile(Paths.getSharedPath(), folder + '/'))
			{
				for (file in Paths.readDirectory(dir))
				{
					if (!file.toLowerCase().endsWith(ext))
						continue;
					var n:String = file.substr(0, file.length - ext.length);
					if (!out.contains(n))
						out.push(n);
				}
			}
		}
		catch (e:Dynamic) {}

		out.sort(function(a:String, b:String):Int
		{
			var x:String = a.toLowerCase();
			var y:String = b.toLowerCase();
			return (x < y) ? -1 : ((x > y) ? 1 : 0);
		});
		return out;
	}
}
