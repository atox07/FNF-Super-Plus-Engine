package states.editors.eventcreator;

/**
 * Modello dati dell'Event Creator.
 *
 * Livello 1 (Metadata)   -> EventProject.name / description / category
 * Livello 2 (Parameters) -> ParamDef
 * Livello 3 (Actions)    -> BlockInstance (istanza) + BlockDef (definizione nella palette JSON)
 *
 * Tutti i valori dei campi sono salvati come STRINGHE ("360", "true", "$target"):
 * la conversione al tipo giusto avviene in EventCodegen, usando il tipo dichiarato.
 */

/** Tipi di parametro disponibili (Livello 2). */
class ParamTypes
{
	public static final ALL:Array<String> = [
		'text', 'int', 'float', 'bool', 'slider', 'dropdown', 'character', 'color', 'sound', 'image', 'stage'
	];

	/** Etichette corte per i bottoni dell'editor (stesso ordine di ALL). */
	public static final LABELS:Array<String> = [
		'Text', 'Int', 'Float', 'Bool', 'Slider', 'List', 'Char', 'Color', 'Sound', 'Image', 'Stage'
	];

	public static function isNumeric(t:String):Bool
		return t == 'int' || t == 'float' || t == 'slider';

	/** Tipi la cui lista di scelte viene enumerata dalle cartelle del gioco/mod (EventPresets). */
	public static function isPreset(t:String):Bool
		return t == 'character' || t == 'sound' || t == 'image' || t == 'stage';
}

/** Un parametro dell'evento (cosa chiede a chi fa la chart). */
class ParamDef
{
	public var name:String;
	public var type:String;

	/** Sempre stringa: "boyfriend", "0.5", "true", "FF00FF". */
	public var defaultValue:String = '';

	/** Per int/float: limitare il valore a min..max. Lo slider usa sempre min/max. */
	public var useRange:Bool = false;

	public var min:Float = 0;
	public var max:Float = 1;
	public var step:Float = 0.05;

	/** Solo per type == 'dropdown'. */
	public var options:Array<String> = [];

	/** true = costante scritta nel .lua, non esposta nel chart. */
	public var fixed:Bool = false;

	public function new(name:String = 'param', type:String = 'text')
	{
		this.name = name;
		this.type = type;
	}
}

/** Un blocco inserito nell'evento (istanza di un BlockDef). */
class BlockInstance
{
	public var id:String;

	/** Oggetto anonimo { chiave: "valore" } (Dynamic per serializzarlo facilmente in JSON). */
	public var fields:Dynamic;

	public function new(id:String)
	{
		this.id = id;
		this.fields = {};
	}

	public function get(key:String):String
	{
		var v:Dynamic = Reflect.field(fields, key);
		return (v == null) ? null : Std.string(v);
	}

	public function set(key:String, value:String):Void
		Reflect.setField(fields, key, value);
}

/** Il progetto completo di un evento. */
class EventProject
{
	public var name:String = 'New Event';
	public var description:String = '';
	public var category:String = 'Visual';

	/** Quanti dei primi parametri non fissi finiscono in value1/value2 (0..2). */
	public var chartValues:Int = 2;

	public var params:Array<ParamDef> = [];
	public var blocks:Array<BlockInstance> = [];

	public function new() {}
}

// ====================================================================
// Palette (caricata da data/eventCreator/blocks.json)
// ====================================================================

/**
 * Campo di un blocco.
 * type: object, text, int, float, bool, color, ease, sound, image, stage, dropdown,
 *       characterfile, auto (numero/bool/stringa dedotto dal valore), code (Lua verbatim),
 *       tag (generato automaticamente, mai mostrato all'utente).
 * La chiave JSON del valore di default e' "def" ("default" e' una parola riservata in Haxe).
 */
typedef BlockFieldDef =
{
	var key:String;
	var label:String;
	var type:String;
	@:optional var def:String;
	@:optional var options:Array<String>;
}

typedef BlockDef =
{
	var id:String;
	var name:String;
	var category:String;
	@:optional var desc:String;
	var fields:Array<BlockFieldDef>;

	/** Template Lua con segnaposto $campo. Le righe multiple si separano con \n. */
	var template:String;

	/** "wait" = blocco speciale: i blocchi successivi finiscono in una continuazione. */
	@:optional var special:String;
}
