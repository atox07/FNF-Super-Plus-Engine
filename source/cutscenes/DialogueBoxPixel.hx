package cutscenes;

import haxe.Json;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.graphics.frames.FlxAtlasFrames;

using StringTools;

/**
 * Dati opzionali nel file .json accanto a ogni scatola:
 * images/custom_dialogs/dialogBoxes/<nome>.json
 * (addY, canFlip, isPixel esistono già nei tuoi file; textX/textY sono nuovi e opzionali)
 */
typedef PixelBoxData =
{
	@:optional var addY:Null<Float>; // sposta la scatola (e il testo) in verticale
	@:optional var canFlip:Null<Bool>; // non usato per ora
	@:optional var isPixel:Null<Bool>; // true = compare nell'editor pixel
	@:optional var textX:Null<Float>; // posizione del testo rispetto all'angolo in alto a sinistra della scatola
	@:optional var textY:Null<Float>;
}

typedef PixelDialogueLine =
{
	var portrait:Null<String>; // nome del personaggio (cartella characters/), '' = nessun ritratto
	var expression:Null<String>; // espressione nell'atlas del ritratto (es. 'default')
	var side:Null<String>; // 'left' | 'right'
	var text:Null<String>;
	var speed:Null<Float>; // secondi per lettera
	@:optional var sound:Null<String>; // suono della battitura (default 'pixelText')
	@:optional var flip:Null<Bool>; // true = ritratto specchiato
}

typedef PixelDialogueFile =
{
	var dialogue:Array<PixelDialogueLine>;
	@:optional var box:Null<String>; // es. 'pixel_normal', 'pixel_mad', 'pixel_spirit'
	@:optional var hand:Null<String>; // es. 'hand_textbox'
	@:optional var bgFadeColor:Null<String>; // es. '#B3DFD8'
	@:optional var textColor:Null<String>;
	@:optional var shadowColor:Null<String>;
	@:optional var portraitScale:Null<Float>;
}

/**
 * Scatola di dialogo in stile Week 6 (pixel), guidata da JSON.
 *
 * Asset (tutti in "images/", cercati in mods/ e in assets/shared/):
 *   custom_dialogs/dialogBoxes/<box>.png + .xml (+ .json)   animazioni: "open" e "normal"
 *   custom_dialogs/dialogHands/<hand>.png                   immagine singola, senza xml
 *   custom_dialogs/dialogPortraits/portrait_<personaggio>.png + .xml            un frame per espressione (es. default0000)
 * Suoni: dal gioco originale (Paths.sound), nessun suono da custom_dialogs.
 */
class DialogueBoxPixel extends FlxSpriteGroup
{
	public static inline var PIXEL_SCALE:Float = 5.4;
	public static inline var DEFAULT_BOX:String = 'pixel_normal';
	public static inline var DEFAULT_HAND:String = 'hand_textbox';
	public static inline var DEFAULT_SOUND:String = 'pixelText';

	static inline var BOXES_FOLDER:String = 'custom_dialogs/dialogBoxes/';
	static inline var HANDS_FOLDER:String = 'custom_dialogs/dialogHands/';
	static inline var PORTRAIT_PREFIX:String = 'custom_dialogs/dialogPortraits/portrait_';
	static inline var BG_ALPHA:Float = 0.7;

	// Come DialogueBox / DialogueBoxPsych, per restare compatibile con School.hx e PlayState
	public var finishThing:Void->Void;
	public var nextDialogueThing:Void->Void = null;
	public var skipDialogueThing:Void->Void = null;

	var data:PixelDialogueFile;
	var previewMode:Bool = false; // usata dall'editor: niente input, niente chiusura

	var bgFade:FlxSprite;
	var box:FlxSprite;
	var boxData:PixelBoxData;
	var hand:FlxSprite;
	var shadowText:FlxText;
	var mainText:FlxText;

	var portraits:Map<String, FlxSprite> = new Map<String, FlxSprite>();
	var missingPortraits:Map<String, Bool> = new Map<String, Bool>();
	var curPortrait:FlxSprite = null;

	var curLine:Int = 0;
	var opened:Bool = false;
	var typing:Bool = false;
	var lineDone:Bool = false;
	var closing:Bool = false;
	var closed:Bool = false;
	var fade:Float = 1;
	var bgAlpha:Float = 0;

	var fullText:String = '';
	var shown:Int = 0;
	var typeTimer:Float = 0;
	var typeSpeed:Float = 0.04;
	var typeSound:String = DEFAULT_SOUND;

	public function new(file:PixelDialogueFile, previewMode:Bool = false)
	{
		super();
		this.previewMode = previewMode;

		if (file.dialogue == null || file.dialogue.length < 1)
			file.dialogue = [emptyLine()];
		data = normalize(file);

		var spirit:Bool = (data.box != null && data.box.indexOf('spirit') != -1);

		// Sfondo colorato
		bgFade = new FlxSprite(-200, -200).makeGraphic(Std.int(FlxG.width * 1.5), Std.int(FlxG.height * 1.5), parseColor(data.bgFadeColor, 0xFFB3DFD8));
		bgFade.scrollFactor.set();
		bgFade.alpha = 0;
		add(bgFade);

		// Scatola
		box = new FlxSprite();
		boxData = loadBox(box, data.box);
		box.scrollFactor.set();
		add(box);

		// Manina
		hand = new FlxSprite();
		var handKey:String = HANDS_FOLDER + data.hand;
		if (Paths.fileExists('images/' + handKey + '.png', IMAGE))
			hand.loadGraphic(Paths.image(handKey));
		else
			hand.makeGraphic(8, 8, 0xFF3F2021);
		hand.scale.set(PIXEL_SCALE, PIXEL_SCALE);
		hand.updateHitbox();
		hand.antialiasing = false;
		hand.scrollFactor.set();
		hand.setPosition(box.x + box.width - 150, box.y + box.height - 95);
		hand.visible = false;
		add(hand);

		// Testo (ombra + testo principale)
		var tx:Float = box.x + (boxData.textX != null ? boxData.textX : box.width * 0.14);
		var ty:Float = box.y + (boxData.textY != null ? boxData.textY : box.height * 0.34);
		var tw:Int = Std.int(box.width * 0.72);
		var pixelFont:String = Paths.font('pixel-latin.ttf');

		shadowText = new FlxText(tx + 2, ty + 2, tw, '', 32);
		shadowText.font = pixelFont;
		shadowText.color = parseColor(data.shadowColor, spirit ? 0xFF000000 : 0xFFD89494);
		shadowText.antialiasing = false;
		shadowText.scrollFactor.set();
		add(shadowText);

		mainText = new FlxText(tx, ty, tw, '', 32);
		mainText.font = pixelFont;
		mainText.color = parseColor(data.textColor, spirit ? 0xFFFFFFFF : 0xFF3F2021);
		mainText.antialiasing = false;
		mainText.scrollFactor.set();
		add(mainText);

		if (previewMode)
		{
			opened = true;
			bgAlpha = BG_ALPHA;
			bgFade.alpha = BG_ALPHA;
		}
		else if (box.animation.exists('open'))
			box.animation.play('open', true);
	}

	// ------------------------------------------------------------------
	// Ciclo di aggiornamento
	// ------------------------------------------------------------------
	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (closed)
			return;

		if (closing)
		{
			fade -= elapsed / 0.8;
			applyFade(fade > 0 ? fade : 0);
			if (fade <= 0)
			{
				closing = false;
				closed = true;
				if (finishThing != null)
					finishThing();
				kill();
			}
			return;
		}

		// Sfondo che appare piano piano
		if (bgAlpha < BG_ALPHA)
		{
			bgAlpha += elapsed * 0.7;
			if (bgAlpha > BG_ALPHA)
				bgAlpha = BG_ALPHA;
			bgFade.alpha = bgAlpha;
		}

		// Attesa fine animazione di apertura della scatola
		if (!opened)
		{
			var cur = box.animation.curAnim;
			if (!box.animation.exists('open') || cur == null || cur.finished)
			{
				opened = true;
				if (box.animation.exists('normal'))
					box.animation.play('normal');
				startLine(0);
			}
			return;
		}

		// Effetto macchina da scrivere
		if (typing)
		{
			typeTimer += elapsed;
			while (typing && typeTimer >= typeSpeed)
			{
				typeTimer -= typeSpeed;
				if (shown < fullText.length)
				{
					shown++;
					if (fullText.charAt(shown - 1).trim().length > 0)
						playTypeSound();
				}
				if (shown >= fullText.length)
					finishTyping(false);
			}
			if (typing)
				setDisplayText(fullText.substr(0, shown));
		}

		if (previewMode)
			return;

		// Input: ENTER/tocco = avanti o completa la riga, BACK = salta tutto
		var back:Bool = #if android FlxG.android.justReleased.BACK || #end Controls.instance.BACK;
		if ((TouchUtil.justPressed || Controls.instance.ACCEPT) || back)
		{
			if (back)
				startClosing();
			else if (lineDone)
				advance();
			else if (typing)
			{
				finishTyping(true);
				playClick();
			}
		}
	}

	// ------------------------------------------------------------------
	// Righe di dialogo
	// ------------------------------------------------------------------
	function startLine(i:Int):Void
	{
		curLine = i;
		var line:PixelDialogueLine = data.dialogue[i];

		fullText = (line.text != null) ? line.text : '';
		shown = 0;
		typeTimer = 0;
		typeSpeed = (line.speed != null && line.speed >= 0.001) ? line.speed : 0.04;
		typeSound = (line.sound != null && line.sound.length > 0) ? line.sound : DEFAULT_SOUND;

		setDisplayText('');
		hand.visible = false;
		lineDone = false;
		typing = true;

		showPortrait(line);

		if (fullText.length < 1)
			finishTyping(false);
	}

	function advance():Void
	{
		if (curLine >= data.dialogue.length - 1)
		{
			startClosing();
			return;
		}
		if (nextDialogueThing != null)
			nextDialogueThing();
		playClick();
		startLine(curLine + 1);
	}

	function finishTyping(userSkip:Bool):Void
	{
		shown = fullText.length;
		setDisplayText(fullText);
		typing = false;
		lineDone = true;
		hand.visible = true;
		if (userSkip && skipDialogueThing != null)
			skipDialogueThing();
	}

	function startClosing():Void
	{
		if (closing || closed)
			return;
		closing = true;
		fade = 1;
		typing = false;
		playClick();
		if (FlxG.sound.music != null)
			FlxG.sound.music.fadeOut(1.5, 0);
	}

	function applyFade(f:Float):Void
	{
		box.alpha = f;
		hand.alpha = f;
		mainText.alpha = f;
		shadowText.alpha = f;
		bgFade.alpha = BG_ALPHA * f;
		if (curPortrait != null)
			curPortrait.alpha = f;
	}

	function setDisplayText(s:String):Void
	{
		mainText.text = s;
		shadowText.text = s;
	}

	function playTypeSound():Void
	{
		if (soundExists(typeSound))
			FlxG.sound.play(Paths.sound(typeSound), 0.8);
	}

	function playClick():Void
	{
		if (soundExists('clickText'))
			FlxG.sound.play(Paths.sound('clickText'), 0.8);
	}

	/** Solo per l'editor: mostra la riga i (instant = testo già completo). */
	public function setPreviewLine(i:Int, instant:Bool):Void
	{
		if (!previewMode || data.dialogue.length < 1)
			return;
		if (i < 0)
			i = 0;
		if (i > data.dialogue.length - 1)
			i = data.dialogue.length - 1;
		startLine(i);
		if (instant)
			finishTyping(false);
	}

	// ------------------------------------------------------------------
	// Ritratti
	// ------------------------------------------------------------------
	function showPortrait(line:PixelDialogueLine):Void
	{
		if (curPortrait != null)
			curPortrait.visible = false;
		curPortrait = null;

		var name:String = line.portrait;
		if (name == null || name.length < 1 || missingPortraits.exists(name))
			return;

		var spr:FlxSprite = portraits.get(name);
		if (spr == null)
		{
			var frames:FlxAtlasFrames = loadPortraitFrames(name);
			if (frames == null)
			{
				missingPortraits.set(name, true);
				return;
			}
			spr = new FlxSprite();
			spr.frames = frames;
			addExpressionAnimations(spr, frames);
			var sc:Float = (data.portraitScale != null && data.portraitScale > 0) ? data.portraitScale : PIXEL_SCALE;
			spr.scale.set(sc, sc);
			spr.antialiasing = false;
			spr.scrollFactor.set();

			// il ritratto sta DIETRO la scatola
			var idx:Int = members.indexOf(box);
			if (idx >= 0)
				insert(idx, spr);
			else
				add(spr);
			portraits.set(name, spr);
		}

		var expr:String = line.expression;
		if (expr == null || !spr.animation.exists(expr))
		{
			var names:Array<String> = spr.animation.getNameList();
			expr = (names.length > 0) ? names[0] : null;
		}
		if (expr != null)
			spr.animation.play(expr, true);

		// espressioni di dimensioni diverse: ricalcolo e allineo sempre al bordo della scatola
		spr.flipX = (line.flip == true);
		spr.updateHitbox();
		spr.x = (line.side == 'right') ? FlxG.width - spr.width - 90 : 90;
		spr.y = box.y - spr.height + 40;
		spr.alpha = 1;
		spr.visible = true;
		curPortrait = spr;
	}

	// ------------------------------------------------------------------
	// Funzioni statiche condivise con l'editor
	// ------------------------------------------------------------------
	static var soundCache:Map<String, Bool> = new Map<String, Bool>();

	/** I suoni vengono presi dal gioco: se il file non c'è, niente suono (e niente "beep"). */
	public static function soundExists(name:String):Bool
	{
		if (name == null || name.length < 1)
			return false;
		if (!soundCache.exists(name))
			soundCache.set(name, Paths.fileExists('sounds/' + name + '.ogg', SOUND));
		return soundCache.get(name);
	}

	static function parseColor(s:Null<String>, def:Int):FlxColor
	{
		if (s != null && s.length > 0)
		{
			var c:Null<FlxColor> = FlxColor.fromString(s);
			if (c != null)
				return c;
		}
		return def;
	}

	static function emptyLine():PixelDialogueLine
	{
		return {
			portrait: '',
			expression: '',
			side: 'left',
			text: '',
			speed: 0.04,
			sound: DEFAULT_SOUND
		};
	}

	/** Riempie i campi mancanti, così un JSON scritto a mano non manda in crash il gioco. */
	public static function normalize(file:PixelDialogueFile):PixelDialogueFile
	{
		if (file == null || file.dialogue == null || file.dialogue.length < 1)
			return null;

		for (line in file.dialogue)
		{
			if (line.portrait == null)
				line.portrait = '';
			if (line.expression == null)
				line.expression = '';
			if (line.side != 'left' && line.side != 'right')
				line.side = 'left';
			if (line.text == null)
				line.text = '';
			if (line.speed == null || line.speed < 0.001)
				line.speed = 0.04;
			if (line.sound == null || line.sound.length < 1)
				line.sound = DEFAULT_SOUND;
		}
		if (file.box == null || file.box.length < 1)
			file.box = DEFAULT_BOX;
		if (file.hand == null || file.hand.length < 1)
			file.hand = DEFAULT_HAND;
		return file;
	}

	/** Cerca data/<canzone>/dialogue-pixel.json (mods e assets). Restituisce null se non esiste. */
	public static function loadDialogueFile(song:String):PixelDialogueFile
	{
		var raw:String = null;
		try
		{
			raw = Paths.getTextFromFile('data/' + song + '/dialogue-pixel.json');
		}
		catch (e:Dynamic) {}

		if (raw == null || raw.length < 1)
			return null;
		if (raw.charCodeAt(0) == 0xFEFF)
			raw = raw.substr(1);

		try
		{
			var file:PixelDialogueFile = cast Json.parse(raw);
			return normalize(file);
		}
		catch (e:Dynamic)
		{
			trace('[DialogueBoxPixel] dialogue-pixel.json is not valid: ' + e);
		}
		return null;
	}

	/** Legge il .json accanto alla scatola (può mancare). */
	public static function readBoxData(name:String):PixelBoxData
	{
		var result:PixelBoxData = {};
		var raw:String = null;
		try
		{
			raw = Paths.getTextFromFile('images/' + BOXES_FOLDER + name + '.json');
		}
		catch (e:Dynamic) {}

		if (raw != null && raw.length > 0)
		{
			if (raw.charCodeAt(0) == 0xFEFF)
				raw = raw.substr(1);
			try
			{
				result = cast Json.parse(raw);
			}
			catch (e:Dynamic)
			{
				trace('[DialogueBoxPixel] box json "' + name + '" is not valid: ' + e);
			}
		}
		return result;
	}

	/**
	 * Carica la scatola `name` dentro lo sprite `box`: frame, animazioni "open"/"normal",
	 * scala pixel e posizione (centrata, in basso). Se i file mancano usa un riquadro bianco.
	 */
	public static function loadBox(box:FlxSprite, name:String):PixelBoxData
	{
		if (name == null || name.length < 1)
			name = DEFAULT_BOX;

		var info:PixelBoxData = readBoxData(name);
		var key:String = BOXES_FOLDER + name;
		var frames:FlxAtlasFrames = null;

		if (Paths.fileExists('images/' + key + '.png', IMAGE) && Paths.fileExists('images/' + key + '.xml', TEXT))
		{
			try
			{
				frames = Paths.getSparrowAtlas(key);
			}
			catch (e:Dynamic)
			{
				trace('[DialogueBoxPixel] box could not be loaded: ' + e);
			}
		}

		if (frames != null && frames.frames != null && frames.frames.length > 0)
		{
			box.frames = frames;
			box.animation.addByPrefix('open', 'open', 24, false);
			box.animation.addByPrefix('normal', 'normal', 24, true);
			if (box.animation.exists('normal'))
				box.animation.play('normal');
			else if (box.animation.exists('open'))
				box.animation.play('open');
		}
		else
		{
			trace('[DialogueBoxPixel] box "' + name + '" not found in images/' + BOXES_FOLDER + ': using a fallback rectangle');
			box.makeGraphic(205, 58, 0xFFFFFFFF);
		}

		box.scale.set(PIXEL_SCALE, PIXEL_SCALE);
		box.updateHitbox();
		box.antialiasing = false;
		box.screenCenter(X);
		box.y = FlxG.height - box.height - 40 + (info.addY != null ? info.addY : 0);
		return info;
	}

	/** Atlas del ritratto: images/custom_dialogs/dialogPortraits/portrait_<nome>.png + .xml. Null se non esiste. */
	public static function loadPortraitFrames(name:String):FlxAtlasFrames
	{
		if (name == null || name.length < 1)
			return null;

		var key:String = PORTRAIT_PREFIX + name;
		if (!Paths.fileExists('images/' + key + '.png', IMAGE) || !Paths.fileExists('images/' + key + '.xml', TEXT))
			return null;

		var frames:FlxAtlasFrames = null;
		try
		{
			frames = Paths.getSparrowAtlas(key);
		}
		catch (e:Dynamic)
		{
			trace('[DialogueBoxPixel] portrait "' + name + '" could not be loaded: ' + e);
		}

		if (frames == null || frames.frames == null || frames.frames.length < 1)
			return null;
		return frames;
	}

	/** Nomi delle espressioni di un atlas ("default0000" -> "default"), senza doppioni. */
	public static function getExpressions(frames:FlxAtlasFrames):Array<String>
	{
		var out:Array<String> = [];
		if (frames == null)
			return out;

		var digits:EReg = ~/[0-9]+$/;
		for (f in frames.frames)
		{
			var n:String = digits.replace(f.name, '');
			if (n.length > 0 && out.indexOf(n) < 0)
				out.push(n);
		}
		return out;
	}

	/** Un'animazione per espressione, costruita sui nomi esatti dei frame (niente confusioni tra "happy" e "happy2"). */
	public static function addExpressionAnimations(spr:FlxSprite, frames:FlxAtlasFrames):Void
	{
		var digits:EReg = ~/[0-9]+$/;
		var order:Array<String> = [];
		var byExpr:Map<String, Array<String>> = new Map<String, Array<String>>();

		for (f in frames.frames)
		{
			var n:String = digits.replace(f.name, '');
			if (n.length < 1)
				continue;
			if (!byExpr.exists(n))
			{
				byExpr.set(n, []);
				order.push(n);
			}
			byExpr.get(n).push(f.name);
		}

		for (n in order)
		{
			var names:Array<String> = byExpr.get(n);
			names.sort(compareStrings);
			spr.animation.addByNames(n, names, 24, false);
		}
	}

	static function compareStrings(a:String, b:String):Int
	{
		if (a < b)
			return -1;
		if (a > b)
			return 1;
		return 0;
	}

	#if MODS_ALLOWED
	/** Cartelle da controllare, dalla più specifica: mod attiva, mods/, assets/shared/ */
	static function collectDirs(sub:String):Array<String>
	{
		var dirs:Array<String> = [];
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			dirs.push(Paths.mods(Mods.currentModDirectory + '/' + sub));
		dirs.push(Paths.mods(sub));
		dirs.push('assets/shared/' + sub);
		return dirs;
	}
	#end

	/** Personaggi = file .json nella cartella "characters/" (FUORI da images). */
	public static function listCharacters():Array<String>
	{
		var out:Array<String> = [];
		#if MODS_ALLOWED
		for (dir in collectDirs('characters/'))
		{
			if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir))
				continue;
			for (file in FileSystem.readDirectory(dir))
			{
				if (!file.endsWith('.json'))
					continue;
				var name:String = file.substr(0, file.length - 5);
				if (out.indexOf(name) < 0)
					out.push(name);
			}
		}
		#end
		out.sort(compareStrings);
		return out;
	}

	/** Scatole pixel = file .json in dialogBoxes/ con "isPixel": true. */
	public static function listBoxes():Array<String>
	{
		var out:Array<String> = [];
		#if MODS_ALLOWED
		for (dir in collectDirs('images/' + BOXES_FOLDER))
		{
			if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir))
				continue;
			for (file in FileSystem.readDirectory(dir))
			{
				if (!file.endsWith('.json'))
					continue;
				var name:String = file.substr(0, file.length - 5);
				if (out.indexOf(name) >= 0)
					continue;

				var pixel:Bool = false;
				try
				{
					var raw:String = File.getContent(dir + file);
					if (raw.charCodeAt(0) == 0xFEFF)
						raw = raw.substr(1);
					var d:PixelBoxData = cast Json.parse(raw);
					pixel = (d != null && d.isPixel == true);
				}
				catch (e:Dynamic) {}

				if (pixel)
					out.push(name);
			}
		}
		#end
		if (out.length < 1)
			out.push(DEFAULT_BOX);
		out.sort(compareStrings);
		return out;
	}
}
