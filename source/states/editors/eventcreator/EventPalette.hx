package states.editors.eventcreator;

import haxe.Json;
import sys.FileSystem;
import sys.io.File;
import backend.Mods;
import backend.Paths;
import states.editors.eventcreator.EventDef;

/**
 * Palette dei blocchi, caricata da  data/eventCreator/blocks.json
 *
 *  - file base:   assets/shared/data/eventCreator/blocks.json
 *  - mod:         mods/<mod>/data/eventCreator/blocks.json  (stesso formato)
 *
 * I blocchi dei mod vengono AGGIUNTI a quelli base; se hanno lo stesso "id"
 * lo sostituiscono. Un mod puo' quindi estendere la palette senza ricompilare.
 */
class EventPalette
{
	public static inline var FILE:String = 'data/eventCreator/blocks.json';

	public static var CATEGORIES:Array<String> = ['Visual', 'Audio', 'Camera', 'Gameplay', 'Other'];

	public static var blocks(default, null):Array<BlockDef> = [];

	/** null se il caricamento e' andato bene. */
	public static var loadError(default, null):String = null;

	static var byId:Map<String, BlockDef> = new Map();

	public static function load():Void
	{
		blocks = [];
		byId = new Map();
		loadError = null;

		var sources:Array<String> = [];

		// 1) palette base (ignora i mod: li leggiamo noi sotto, uno per uno)
		try
		{
			var base:String = Paths.getTextFromFile(FILE, true);
			if (base != null && base.length > 0)
				sources.push(base);
		}
		catch (e:Dynamic) {}

		// 2) palette dei mod (e copia base su disco, se esiste: il merge per id e' idempotente)
		#if MODS_ALLOWED
		try
		{
			for (path in Mods.directoriesWithFile(Paths.getSharedPath(), FILE))
			{
				if (FileSystem.exists(path))
					sources.push(File.getContent(path));
			}
		}
		catch (e:Dynamic) {}
		#end

		for (src in sources)
		{
			try
			{
				var data:Dynamic = Json.parse(src);
				var list:Array<Dynamic> = data.blocks;
				if (list == null)
					continue;

				for (b in list)
				{
					var def:BlockDef = cast b;
					if (def == null || def.id == null || def.template == null || def.fields == null)
						continue;

					if (byId.exists(def.id))
						blocks[blocks.indexOf(byId.get(def.id))] = def;
					else
						blocks.push(def);
					byId.set(def.id, def);
				}
			}
			catch (e:Dynamic)
			{
				loadError = 'blocks.json: ' + Std.string(e);
			}
		}

		if (blocks.length == 0 && loadError == null)
			loadError = 'Palette file not found: assets/shared/' + FILE;
	}

	public static function get(id:String):BlockDef
		return (id == null) ? null : byId.get(id);

	public static function inCategory(cat:String):Array<BlockDef>
		return blocks.filter(function(b:BlockDef):Bool return b.category == cat);
}
