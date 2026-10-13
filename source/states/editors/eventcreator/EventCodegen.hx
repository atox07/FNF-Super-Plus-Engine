package states.editors.eventcreator;

import haxe.Json;

using StringTools;

typedef GenResult =
{
	var code:String;
	var errors:Array<String>;
	var warnings:Array<String>;
}

/** Stato di una singola generazione (contatore tag, errori, parametri noti...). */
private class GenCtx
{
	public var eventId:String;
	public var slug:String;
	public var tagCounter:Int = 0;
	public var usesWait:Bool = false;
	public var errors:Array<String> = [];
	public var warnings:Array<String> = [];

	/** variabili Lua dei parametri (ident -> ident) */
	public var paramIdents:Map<String, String> = new Map();

	public function new(eventId:String, slug:String)
	{
		this.eventId = eventId;
		this.slug = slug;
	}

	/** Tag univoco per questo call site: ec_<evento>_<n>. */
	public function newTag():String
	{
		tagCounter++;
		return 'ec_' + slug + '_' + tagCounter;
	}

	/** Nome della variabile Lua di un parametro, o null se non esiste. */
	public function paramRef(name:String):String
	{
		if (paramIdents.exists(name))
			return name;
		var id:String = EventCodegen.ident(name);
		return paramIdents.exists(id) ? id : null;
	}
}

/**
 * Genera il file .lua di un evento a partire da un EventProject.
 *
 * Il Lua prodotto e' codice normale e leggibile:
 *  - callback globale onEvent(eventName, value1, value2, strumTime) con guard sul nome
 *    (PlayState chiama onEvent su TUTTI gli script per OGNI evento del chart);
 *  - i parametri diventano variabili locali (con default applicato anche a stringhe vuote);
 *  - i blocchi diventano chiamate alle funzioni Lua reali del motore;
 *  - Wait -> runTimer + continuazione salvata in ec_pending, richiamata da onTimerCompleted;
 *  - un header --[==[EC ... EC]==] con il progetto in JSON, per poter riaprire l'evento.
 */
class EventCodegen
{
	/** EventNote ha solo value1 e value2 (formato chart). */
	public static inline var MAX_CHART_VALUES:Int = 2;

	static inline var INDENT:String = '    ';

	/** Eventi gestiti da PlayState.triggerEvent / eventEarlyTrigger (minuscolo). */
	public static final BUILTIN_EVENTS:Array<String> = [
		'hey!', 'set gf speed', 'add camera zoom', 'set camera bopping', 'play animation',
		'camera follow pos', 'alt idle animation', 'screen shake', 'change stage',
		'change character', 'change scroll speed', 'set property', 'play sound',
		'lyric event', 'kill henchmen'
	];

	static final LUA_RESERVED:Array<String> = [
		'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in',
		'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while'
	];

	/** Nomi che il codice generato usa gia': un parametro non puo' chiamarsi cosi. */
	static final RESERVED_LOCALS:Array<String> = [
		'eventName', 'value1', 'value2', 'strumTime', 'ec_str', 'ec_num', 'ec_bool', 'ec_pending',
		'math', 'string', 'table', 'tostring', 'tonumber'
	];

	// ================================================================
	// NOMI
	// ================================================================

	/**
	 * ID evento = nome file = nome mostrato nel Chart Editor.
	 * Si tolgono solo i caratteri non validi nei nomi file; maiuscole e spazi restano.
	 */
	public static function eventId(s:String):String
	{
		if (s == null)
			return 'New Event';
		var out:String = s.trim();
		out = ~/[\\\/:*?"<>|]+/g.replace(out, '_');
		out = ~/[. ]+$/.replace(out, '');
		if (out.length < 1)
			out = 'New Event';
		return out;
	}

	/** Nome di variabile Lua valido a partire dal nome di un parametro. */
	public static function ident(name:String):String
	{
		var s:String = (name == null) ? '' : name.trim();
		s = ~/[^A-Za-z0-9_]+/g.replace(s, '_');
		s = ~/^_+|_+$/g.replace(s, '');
		if (s.length < 1)
			s = 'param';
		if (~/^[0-9]/.match(s))
			s = 'p_' + s;
		if (LUA_RESERVED.contains(s) || RESERVED_LOCALS.contains(s))
			s += '_';
		return s;
	}

	static function slug(s:String):String
	{
		var o:String = ~/[^a-z0-9]+/g.replace(s.toLowerCase(), '_');
		o = ~/^_+|_+$/g.replace(o, '');
		return (o.length < 1) ? 'event' : o;
	}

	// ================================================================
	// LITERAL LUA
	// ================================================================

	public static function esc(s:String):String
	{
		if (s == null)
			s = '';
		s = s.replace('\\', '\\\\');
		s = s.replace('"', '\\"');
		s = s.replace('\n', '\\n');
		s = s.replace('\r', '\\r');
		s = s.replace('\t', '\\t');
		return '"' + s + '"';
	}

	public static function fmtNum(f:Float):String
	{
		if (Math.isNaN(f) || !Math.isFinite(f))
			return '0';
		return Std.string(f);
	}

	static function parseNum(s:String, fallback:Float):Float
	{
		if (s == null)
			return fallback;
		var f:Float = Std.parseFloat(s);
		return Math.isNaN(f) ? fallback : f;
	}

	static function stripHash(s:String):String
	{
		if (s == null)
			return '';
		s = s.trim();
		return (s.charAt(0) == '#') ? s.substr(1) : s;
	}

	static function oneLine(s:String):String
	{
		if (s == null)
			return '';
		return s.replace('\r', ' ').replace('\n', ' ');
	}

	// ================================================================
	// PARAMETRI
	// ================================================================

	/**
	 * Per ogni parametro: 0 = fisso (costante nel .lua), 1 = value1, 2 = value2.
	 * Esposti: i primi N parametri non fissi, con N = chartValues (max 2).
	 */
	public static function exposure(p:EventProject):Array<Int>
	{
		var limit:Int = Std.int(Math.max(0, Math.min(p.chartValues, MAX_CHART_VALUES)));
		var out:Array<Int> = [];
		var used:Int = 0;
		for (q in p.params)
		{
			if (!q.fixed && used < limit)
			{
				used++;
				out.push(used);
			}
			else
				out.push(0);
		}
		return out;
	}

	/** Valore di default del parametro come literal Lua. */
	static function paramDefault(q:ParamDef):String
	{
		switch (q.type)
		{
			case 'int':
				return fmtNum(Math.floor(parseNum(q.defaultValue, 0)));
			case 'float', 'slider':
				return fmtNum(parseNum(q.defaultValue, 0));
			case 'bool':
				return (q.defaultValue == 'true' || q.defaultValue == '1') ? 'true' : 'false';
			case 'color':
				return esc(stripHash(q.defaultValue));
			default:
				return esc(q.defaultValue);
		}
	}

	static function clampExpr(q:ParamDef, expr:String):String
	{
		var ranged:Bool = (q.type == 'slider') || q.useRange;
		if (!ranged)
			return expr;
		return 'math.max(' + fmtNum(q.min) + ', math.min(' + fmtNum(q.max) + ', ' + expr + '))';
	}

	/** Espressione Lua che legge il parametro dal valore del chart (ref = value1 / value2). */
	static function bindingExpr(q:ParamDef, ref:String, helpers:Map<String, Bool>):String
	{
		var d:String = paramDefault(q);
		switch (q.type)
		{
			case 'int':
				helpers.set('num', true);
				return clampExpr(q, 'math.floor(ec_num(' + ref + ', ' + d + '))');
			case 'float', 'slider':
				helpers.set('num', true);
				return clampExpr(q, 'ec_num(' + ref + ', ' + d + ')');
			case 'bool':
				helpers.set('bool', true);
				return 'ec_bool(' + ref + ', ' + d + ')';
			default:
				helpers.set('str', true);
				return 'ec_str(' + ref + ', ' + d + ')';
		}
	}

	static function bindingLineH(p:EventProject, index:Int, helpers:Map<String, Bool>):String
	{
		var q:ParamDef = p.params[index];
		var id:String = ident(q.name);
		var slot:Int = exposure(p)[index];
		if (slot > 0)
			return 'local ' + id + ' = ' + bindingExpr(q, 'value' + slot, helpers);
		return 'local ' + id + ' = ' + paramDefault(q) + '  -- fixed (not exposed in the chart)';
	}

	/** La riga "local x = ..." che verra' generata per il parametro (per l'anteprima nella UI). */
	public static function bindingLine(p:EventProject, index:Int):String
		return bindingLineH(p, index, new Map());

	// ================================================================
	// DESCRIZIONE (.txt letto dal Chart Editor)
	// ================================================================

	public static function paramSummary(q:ParamDef):String
	{
		var s:String = q.name + ' (' + q.type;
		if (q.type == 'slider' || ((q.type == 'int' || q.type == 'float') && q.useRange))
			s += ' ' + fmtNum(q.min) + '-' + fmtNum(q.max);
		if (q.type == 'dropdown' && q.options.length > 0)
			s += ': ' + q.options.join('/');
		s += ', default ' + q.defaultValue + ')';
		return s;
	}

	/** Una riga: "[Categoria] descrizione | V1: ... | V2: ..." (cosi' il Chart Editor mostra cosa fa ogni valore). */
	public static function generateDescription(p:EventProject):String
	{
		var base:String = (p.description != null && p.description.trim().length > 0) ? p.description : p.name;
		var s:String = '[' + p.category + '] ' + oneLine(base);

		var expo:Array<Int> = exposure(p);
		var parts:Array<String> = [];
		for (i in 0...p.params.length)
			if (expo[i] > 0)
				parts.push('V' + expo[i] + ': ' + paramSummary(p.params[i]));
		if (parts.length > 0)
			s += ' | ' + parts.join(' | ');
		return s;
	}

	// ================================================================
	// HEADER DI ROUND-TRIP
	// ================================================================

	static function paramToObj(q:ParamDef):Dynamic
	{
		return {
			name: q.name,
			type: q.type,
			def: q.defaultValue,
			useRange: q.useRange,
			min: q.min,
			max: q.max,
			step: q.step,
			options: q.options,
			fixed: q.fixed
		};
	}

	static function encodeHeader(p:EventProject):String
	{
		var blocks:Array<Dynamic> = [];
		for (b in p.blocks)
			blocks.push({id: b.id, fields: b.fields});

		var params:Array<Dynamic> = [];
		for (q in p.params)
			params.push(paramToObj(q));

		var payload:Dynamic = {
			format: 1,
			name: p.name,
			description: p.description,
			category: p.category,
			chartValues: p.chartValues,
			parameters: params,
			blocks: blocks
		};
		var json:String = Json.stringify(payload, null, '    ');

		// livello di parentesi lunga che non compare nel JSON
		var eq:String = '==';
		while (json.indexOf(']' + eq + ']') >= 0)
			eq += '=';

		return '--[' + eq + '[EC\n' + json + '\nEC]' + eq + ']';
	}

	// ================================================================
	// BLOCCHI
	// ================================================================

	static function findField(def:BlockDef, key:String):BlockFieldDef
	{
		for (f in def.fields)
			if (f.key == key)
				return f;
		return null;
	}

	/** Sostituisce $parametro con la variabile Lua; il resto del testo resta com'e'. */
	static function substituteParams(raw:String, ctx:GenCtx):String
	{
		var re:EReg = ~/\$([A-Za-z_][A-Za-z0-9_]*)/g;
		return re.map(raw, function(r:EReg):String
		{
			var ref:String = ctx.paramRef(r.matched(1));
			return (ref != null) ? ref : r.matched(0);
		});
	}

	/** Literal Lua del valore di un campo di blocco. */
	static function fieldLiteral(def:BlockDef, f:BlockFieldDef, inst:BlockInstance, ctx:GenCtx):String
	{
		if (f.type == 'tag')
			return esc(ctx.newTag());

		var raw:String = inst.get(f.key);
		if (raw == null)
			raw = (f.def != null) ? f.def : '';

		// via di fuga: "$lua:<espressione>" viene scritta cosi' com'e'
		if (raw.startsWith("$lua:"))
			return raw.substr(5);

		if (f.type == 'code')
			return substituteParams(raw, ctx);

		// riferimento a un parametro: "$nome"
		var refRe:EReg = ~/^\$([A-Za-z_][A-Za-z0-9_]*)$/;
		if (refRe.match(raw))
		{
			var ref:String = ctx.paramRef(refRe.matched(1));
			if (ref != null)
				return ref;
			ctx.warnings.push('Field "' + f.label + '" of "' + def.name + '" refers to the missing parameter "' + raw + '".');
			return 'nil';
		}

		switch (f.type)
		{
			case 'int':
				return fmtNum(Math.floor(parseNum(raw, parseNum(f.def, 0))));
			case 'float':
				return fmtNum(parseNum(raw, parseNum(f.def, 0)));
			case 'bool':
				return (raw == 'true' || raw == '1') ? 'true' : 'false';
			case 'color':
				return esc(stripHash(raw));
			case 'auto':
				if (~/^-?[0-9]+(\.[0-9]+)?$/.match(raw))
					return raw;
				if (raw == 'true' || raw == 'false')
					return raw;
				return esc(raw);
			default:
				return esc(raw);
		}
	}

	static function expand(def:BlockDef, inst:BlockInstance, ctx:GenCtx):String
	{
		var re:EReg = ~/\$([A-Za-z_][A-Za-z0-9_]*)/g;
		return re.map(def.template, function(r:EReg):String
		{
			var key:String = r.matched(1);
			var f:BlockFieldDef = findField(def, key);
			if (f != null)
				return fieldLiteral(def, f, inst, ctx);

			var ref:String = ctx.paramRef(key);
			if (ref != null)
				return ref;

			ctx.warnings.push("\"$" + key + "\" in the template of \"" + def.name + "\" matches no field or parameter.");
			return 'nil';
		});
	}

	static function repeatIndent(depth:Int):String
	{
		var s:String = '';
		for (i in 0...depth)
			s += INDENT;
		return s;
	}

	/**
	 * Scrive i blocchi da 'start' in poi. Un blocco Wait chiude il livello corrente:
	 * tutto cio' che lo segue finisce in una funzione salvata in ec_pending[tag]
	 * (closure: i parametri restano visibili), richiamata da onTimerCompleted.
	 */
	static function emitBlocks(blocks:Array<BlockInstance>, start:Int, depth:Int, L:Array<String>, ctx:GenCtx):Void
	{
		var ind:String = repeatIndent(depth);
		var i:Int = start;
		while (i < blocks.length)
		{
			var inst:BlockInstance = blocks[i];
			var def:BlockDef = EventPalette.get(inst.id);

			if (def == null)
			{
				L.push(ind + '-- [UNKNOWN BLOCK: ' + inst.id + ']');
				ctx.warnings.push('Unknown block "' + inst.id + '" (not in the palette): skipped.');
				i++;
				continue;
			}

			if (def.special == 'wait')
			{
				var f:BlockFieldDef = findField(def, 'seconds');
				var secs:String = (f != null) ? fieldLiteral(def, f, inst, ctx) : '0.5';
				var tag:String = ctx.newTag();
				ctx.usesWait = true;

				L.push(ind + '-- [' + def.name + ']');
				L.push(ind + 'runTimer(' + esc(tag) + ', ' + secs + ')');
				L.push(ind + 'ec_pending[' + esc(tag) + '] = function()');
				if (i + 1 >= blocks.length)
					L.push(ind + INDENT + '-- (nothing after the wait)');
				else
					emitBlocks(blocks, i + 1, depth + 1, L, ctx);
				L.push(ind + 'end');
				return;
			}

			if (def.id == 'trigger_event')
			{
				var target:String = inst.get('event');
				if (target != null && eventId(target).toLowerCase() == ctx.eventId.toLowerCase())
					ctx.errors.push('"Trigger Event" calls this same event: it would loop forever.');
			}

			L.push(ind + '-- [' + def.name + ']');
			for (line in expand(def, inst, ctx).split('\n'))
				if (line.trim().length > 0)
					L.push(ind + line);
			i++;
		}
	}

	// ================================================================
	// GENERAZIONE
	// ================================================================

	/**
	 * Genera il .lua. Con withHeader = false salta il blocco JSON di round-trip
	 * (utile per l'anteprima: l'header e' lungo e nasconderebbe il codice).
	 */
	public static function generate(p:EventProject, withHeader:Bool = true):GenResult
	{
		var id:String = eventId(p.name);
		var ctx:GenCtx = new GenCtx(id, slug(id));
		var helpers:Map<String, Bool> = new Map();

		// ---- validazione ----
		if (p.name == null || p.name.trim().length < 1)
			ctx.errors.push('Event name is empty.');
		if (BUILTIN_EVENTS.contains(id.toLowerCase()))
			ctx.errors.push('"' + id + '" is a built-in event name: choose another one.');

		var limit:Int = Std.int(Math.max(0, Math.min(p.chartValues, MAX_CHART_VALUES)));
		var nonFixed:Int = 0;
		for (i in 0...p.params.length)
		{
			var q:ParamDef = p.params[i];
			var pid:String = ident(q.name);

			if (q.name == null || q.name.trim().length < 1)
				ctx.errors.push('Parameter #' + (i + 1) + ' has no name.');
			else if (pid != q.name)
				ctx.warnings.push('Parameter "' + q.name + '" becomes the Lua variable "' + pid + '".');

			if (ctx.paramIdents.exists(pid))
				ctx.errors.push('Two parameters use the same Lua variable "' + pid + '".');
			ctx.paramIdents.set(pid, pid);

			if (!q.fixed)
				nonFixed++;
			if (q.type == 'dropdown' && q.options.length < 1)
				ctx.warnings.push('Parameter "' + q.name + '" is a list without options.');
			if ((q.type == 'slider' || ((q.type == 'int' || q.type == 'float') && q.useRange)) && q.min > q.max)
				ctx.errors.push('Parameter "' + q.name + '": min is greater than max.');
		}
		if (nonFixed > limit)
			ctx.warnings.push(nonFixed + ' non-fixed parameters but only ' + limit + ' chart value(s): the extra ones become constants.');

		// ---- corpo di onEvent (prima del resto: serve sapere quali helper usare) ----
		var body:Array<String> = [];
		if (p.params.length > 0)
		{
			body.push(INDENT + '-- ===== parameters =====');
			for (i in 0...p.params.length)
				body.push(INDENT + bindingLineH(p, i, helpers));
			body.push('');
		}
		if (p.blocks.length < 1)
			body.push(INDENT + '-- no actions yet');
		else
			emitBlocks(p.blocks, 0, 1, body, ctx);

		// ---- assemblaggio ----
		var L:Array<String> = [];
		L.push('-- ============================================================');
		L.push('--  ' + oneLine(p.name));
		L.push('--  Generated by Event Creator (Super Plus Engine)');
		L.push('--  You can edit this file by hand: it is normal Lua code.');
		L.push('-- ============================================================');
		if (withHeader)
			L.push(encodeHeader(p));
		else
			L.push('-- (round-trip header hidden in the preview)');
		L.push('');

		var anyHelper:Bool = false;
		if (helpers.exists('str'))
		{
			L.push('local function ec_str(v, d)');
			L.push(INDENT + 'if v == nil or v == "" then return d end');
			L.push(INDENT + 'return tostring(v)');
			L.push('end');
			L.push('');
			anyHelper = true;
		}
		if (helpers.exists('num'))
		{
			L.push('local function ec_num(v, d)');
			L.push(INDENT + 'local n = tonumber(v)');
			L.push(INDENT + 'if n == nil then return d end');
			L.push(INDENT + 'return n');
			L.push('end');
			L.push('');
			anyHelper = true;
		}
		if (helpers.exists('bool'))
		{
			L.push('local function ec_bool(v, d)');
			L.push(INDENT + 'if v == nil or v == "" then return d end');
			L.push(INDENT + 'v = tostring(v):lower()');
			L.push(INDENT + "return v == 'true' or v == '1'");
			L.push('end');
			L.push('');
			anyHelper = true;
		}

		if (ctx.usesWait)
		{
			L.push('-- continuations of the "Wait" blocks, run by onTimerCompleted');
			L.push('local ec_pending = {}');
			L.push('');
		}

		L.push('function onEvent(eventName, value1, value2, strumTime)');
		L.push(INDENT + '-- onEvent is called for EVERY event of the chart: react only to ours');
		L.push(INDENT + 'if eventName ~= ' + esc(id) + ' then return end');
		L.push('');
		for (line in body)
			L.push(line);
		L.push('end');
		L.push('');

		if (ctx.usesWait)
		{
			L.push('function onTimerCompleted(tag)');
			L.push(INDENT + 'local fn = ec_pending[tag]');
			L.push(INDENT + 'if fn then');
			L.push(INDENT + INDENT + 'ec_pending[tag] = nil');
			L.push(INDENT + INDENT + 'fn()');
			L.push(INDENT + 'end');
			L.push('end');
			L.push('');
		}

		return {
			code: L.join('\n'),
			errors: ctx.errors,
			warnings: ctx.warnings
		};
	}
}
