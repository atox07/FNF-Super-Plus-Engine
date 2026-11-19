package states.editors.luablocks;

import haxe.Json;
import haxe.crypto.Base64;
import haxe.io.Bytes;
import states.editors.eventcreator.EventDef.BlockDef;
import states.editors.eventcreator.EventDef.BlockFieldDef;

using StringTools;

typedef LuaBlockHat =
{
	var id:String;
	var label:String;
	var params:Array<String>;
	var ?filterLabel:String;
	var ?filterExpr:String;
}

typedef LuaBlockValue =
{
	var text:String;
	var source:String;
}

typedef LuaBlock =
{
	var id:String;
	var values:Array<LuaBlockValue>;
}

typedef LuaBlockStack =
{
	var hat:String;
	var filter:String;
	var blocks:Array<LuaBlock>;
}

class LuaBlocksProject
{
	public static inline var MAX_STACKS:Int = 32;
	public static inline var MAX_BLOCKS:Int = 64;
	static inline var HEADER:String = '-- Lua Blocks project v1 ';

	public static final hats:Array<LuaBlockHat> = [
		{id: 'onCreate', label: 'On create', params: []},
		{id: 'onSongStart', label: 'On song start', params: []},
		{id: 'onUpdate', label: 'On update', params: ['elapsed']},
		{id: 'onBeatHit', label: 'On beat', params: ['curBeat'], filterLabel: 'Beat (optional)', filterExpr: 'curBeat'},
		{id: 'onStepHit', label: 'On step', params: ['curStep'], filterLabel: 'Step (optional)', filterExpr: 'curStep'},
		{id: 'onEvent', label: 'On event', params: ['name', 'v1', 'v2', 'strumTime'], filterLabel: 'Event name (optional)', filterExpr: 'name'},
		{id: 'onTimerCompleted', label: 'On timer', params: ['tag', 'loops', 'loopsLeft'], filterLabel: 'Timer tag (optional)', filterExpr: 'tag'}
	];

	public var name:String = 'New Script';
	public var song:String = '';
	public var stacks:Array<LuaBlockStack> = [];

	public function new() {}

	public static function getHat(id:String):LuaBlockHat
	{
		for (hat in hats)
			if (hat.id == id)
				return hat;
		return null;
	}

	public static function editableFields(def:BlockDef):Array<BlockFieldDef>
		return def.fields.filter(field -> field.type != 'tag');

	public static function newBlock(def:BlockDef):LuaBlock
		return {id: def.id, values: [for (field in editableFields(def)) {text: field.def ?? '', source: ''}]};

	public function encode(code:String):String
	{
		var payload = Base64.encode(Bytes.ofString(Json.stringify({name: name, song: song, stacks: stacks})));
		return HEADER + payload + '\n' + code;
	}

	public static function decode(code:String, palette:Map<String, BlockDef>):LuaBlocksProject
	{
		if (code.startsWith('\uFEFF'))
			code = code.substr(1);
		var end = code.indexOf('\n');
		if (end < 0 || !code.startsWith(HEADER))
			throw 'Choose a .lua exported from Lua Blocks Editor.';

		var raw:Dynamic = Json.parse(Base64.decode(code.substring(HEADER.length, end).trim()).toString());
		var project = new LuaBlocksProject();
		project.name = readString(raw, 'name');
		project.song = readString(raw, 'song');
		for (data in readArray(raw, 'stacks', MAX_STACKS))
		{
			var hat = getHat(readString(data, 'hat'));
			if (hat == null)
				throw 'Unknown callback in project.';
			var stack:LuaBlockStack = {hat: hat.id, filter: readString(data, 'filter'), blocks: []};
			for (entry in readArray(data, 'blocks', MAX_BLOCKS))
			{
				var id = readString(entry, 'id');
				var def = palette.get(id);
				if (def == null)
					throw 'Unknown block in project: ' + id;
				var values = readArray(entry, 'values', editableFields(def).length);
				if (values.length != editableFields(def).length)
					throw 'Invalid arguments for ' + def.name;
				var block:LuaBlock = {id: id, values: []};
				for (value in values)
				{
					var source = readString(value, 'source');
					if (source != '' && !hat.params.contains(source))
						throw 'Unavailable parameter in ' + hat.id + ': ' + source;
					block.values.push({text: readString(value, 'text'), source: source});
				}
				stack.blocks.push(block);
			}
			project.stacks.push(stack);
		}
		return project;
	}

	public static function body(code:String):String
	{
		var end = code.indexOf('\n');
		return end < 0 ? '' : code.substr(end + 1).replace('\r\n', '\n').trim();
	}

	static function readString(data:Dynamic, key:String):String
	{
		var value:Dynamic = Reflect.field(data, key);
		if (!Std.isOfType(value, String))
			throw 'Invalid project field: ' + key;
		return cast value;
	}

	static function readArray(data:Dynamic, key:String, max:Int):Array<Dynamic>
	{
		var value:Dynamic = Reflect.field(data, key);
		if (!Std.isOfType(value, Array))
			throw 'Invalid project list: ' + key;
		var list:Array<Dynamic> = cast value;
		if (list.length > max)
			throw 'Too many items in ' + key;
		return list;
	}
}
