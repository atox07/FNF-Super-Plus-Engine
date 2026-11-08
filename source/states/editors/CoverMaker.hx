package states.editors;

#if sys
import flixel.FlxG;
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxState;
import flixel.FlxSprite;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import openfl.media.Sound;
import openfl.geom.Rectangle;
import lime.media.AudioBuffer;
import lime.ui.FileDialog;
import lime.ui.FileDialogType;
import haxe.io.Bytes;
import sys.io.File;
import sys.FileSystem;
import backend.MusicBeatSubstate;
import states.editors.CoverMidi.CoverNote;

/**
	Cover Maker - interfaccia Flixel in stile FNF.
	Motore audio e MIDI: CoverVoice / CoverMidi (invariati, piu' preview di nota e sliceCount).

	Layout: 3 file di bottoni | righello | Inst | Dad | BF | piano roll della traccia selezionata.
**/
class CoverMaker extends MusicBeatSubstate
{
	// ---- layout (schermo 1280x720) ----
	static inline var X0:Int = 120; // inizio timeline
	static inline var X1:Int = 1270; // fine timeline
	static inline var RULER_Y:Int = 150;
	static inline var INST_Y:Int = 242; // Inst sotto Dad e BF
	static inline var LANE_H:Int = 30;
	static inline var ROLL_Y:Int = 288;
	static inline var ROW_H:Int = 16;
	static inline var ROWS:Int = 24;
	static final LANE_Y:Array<Int> = [174, 208];

	// ---- barra menu ----
	static inline var MENU_Y:Int = 34;
	static inline var MENU_H:Int = 24;
	static inline var MENU_W:Int = 84;
	static inline var MENU_ITEM_W:Int = 220;
	static inline var MENU_ITEM_H:Int = 22;
	static inline var MENU_LAYER_H:Int = 280;

	// ---- colori ----
	static inline var BG:Int = 0xFF14161F;
	static inline var LANE_BG:Int = 0xFF2B3248;
	static inline var LANE_BG_ON:Int = 0xFF3C4766;
	static inline var ROW_LIGHT:Int = 0xFF323C50;
	static inline var ROW_DARK:Int = 0xFF242C3D;
	static inline var ROW_SLICE:Int = 0xFF3B4D63;
	static final TRACK_COLOR:Array<Int> = [0xFFC391EF, 0xFF68D6CB];

	// ---- progetto ----
	var songName:String;
	var projectBpm:Float;
	var gridSec:Float; // 1 step in secondi
	var voices:Array<CoverVoice> = [new CoverVoice(), new CoverVoice()]; // 0 = Dad (Opponent), 1 = BF (Player)
	var instPath:String = '';
	var instLoaded:Bool = false;
	var track:Int = 0;
	var selected:CoverNote = null;

	// ---- vista ----
	var secondsPerPage:Float = 8;
	var page:Float = 0;
	var low:Int = 48;
	var dirty:Bool = true;

	// ---- transport ----
	var playing:Bool = false;
	var cursor:Float = 0;
	var origin:Float = 0;
	var started:Float = 0;
	var startedAt:Float = 0;

	// ---- audio ----
	var instSnd:FlxSound;
	var voiceSnd:Array<FlxSound> = [];
	var previewSnd:FlxSound;
	var rendered:Array<Sound> = [null, null];
	var renderDirty:Array<Bool> = [true, true];
	var renderedEnd:Array<Float> = [0, 0];

	// ---- mouse ----
	var drag:String = '';
	var dragMx:Float = 0;
	var dragMy:Float = 0;
	var oldValue:Float = 0;
	var oldPitch:Int = 0;

	// ---- UI ----
	var canvas:FlxSprite;
	var statusText:FlxText;
	var infoText:FlxText;
	var pool:Array<FlxText> = [];
	var poolIdx:Int = 0;
	var rectTmp:Rectangle = new Rectangle();
	var dialog:FileDialog;
	var catalog:Array<String> = [];
	var songIndex:Int = -1;

	// ---- isolamento dal chart editor ----
	var coverCam:FlxCamera;
	var menus:Array<{name:String, items:Array<{label:String, fn:Void->Void, keep:Bool}>}> = [];
	var menuOpen:Int = -1;
	var menuHover:Int = -1; // >=0 voce, <=-2 intestazione (-2 - i)
	var menuLayer:FlxSprite;
	var mpool:Array<FlxText> = [];
	var mpoolIdx:Int = 0;
	var parentState:FlxState;
	var parentDraw:Bool = true;
	var parentUpdate:Bool = false;
	var parentSaved:Bool = false;

	public function new(song:String, bpm:Float)
	{
		super();
		songName = song;
		projectBpm = bpm > 0 ? bpm : 120;
		gridSec = 60 / projectBpm / 4;
	}

	override function create()
	{
		super.create();
		FlxG.mouse.visible = true;

		// Camera dedicata sopra TUTTE le camere del chart editor (camHUD/camUI ecc.),
		// altrimenti i menu e i tab del chart restano disegnati sopra il Cover Maker.
		coverCam = new FlxCamera();
		coverCam.bgColor = BG;
		FlxG.cameras.add(coverCam, false);
		cameras = [coverCam];

		// Nascondi e metti in pausa lo state sotto finche' il Cover Maker e' aperto.
		parentState = FlxG.state;
		if (parentState != null && parentState != this)
		{
			parentDraw = parentState.persistentDraw;
			parentUpdate = parentState.persistentUpdate;
			parentState.persistentDraw = false;
			parentState.persistentUpdate = false;
			parentSaved = true;
		}

		canvas = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, BG, true);
		canvas.scrollFactor.set();
		add(canvas);

		instSnd = newSound();
		voiceSnd = [newSound(), newSound()];
		previewSnd = newSound();

		for (i in 0...44)
		{
			var t:FlxText = mkText(0, 0, 120, '', 12, FlxColor.WHITE);
			t.visible = false;
			pool.push(t);
			add(t);
		}

		add(mkText(10, 6, 400, 'COVER MAKER', 22, 0xFFFFFFFF));

		buildMenus();

		statusText = mkText(10, 70, FlxG.width - 20, '', 14, 0xFFFFE08A);
		add(statusText);
		infoText = mkText(10, 94, FlxG.width - 20, '', 13, 0xFFB8C0D8);
		add(infoText);

		var hint:FlxText = mkText(10, ROLL_Y + ROWS * ROW_H + 6, FlxG.width - 20,
			'SPACE play/pausa | ENTER stop | ESC chiudi | DEL cancella nota | click righello = sposta cursore | trascina corsia Dad/BF = sposta pattern\n'
			+ 'Piano roll: click = nuova nota, trascina = sposta, bordo destro = allunga, click destro = elimina | rotella = scorri, CTRL+rotella = zoom, SHIFT+rotella = ottava',
			12, 0xFF7F88A8);
		hint.wordWrap = true;
		add(hint);

		// Barra dei menu: sempre sopra tutto il resto (overlay + testi propri)
		menuLayer = new FlxSprite(0, 0).makeGraphic(FlxG.width, MENU_LAYER_H, 0x00000000, true);
		menuLayer.scrollFactor.set();
		add(menuLayer);
		for (i in 0...20)
		{
			var t:FlxText = mkText(0, 0, 260, '', 13, FlxColor.WHITE);
			t.wordWrap = false;
			t.visible = false;
			mpool.push(t);
			add(t);
		}
		redrawMenu();

		try
		{
			var s:Sound = Paths.inst(songName);
			if (s != null)
				setInst(s, '');
		}
		catch (e:Dynamic)
			setStatus(Std.string(e));

		setStatus('Carica un MIDI e una voce per Dad e BF. La voce viene tagliata nei silenzi: la nota root + N suona la fetta N.');
		updateInfo();
		dirty = true;
	}

	// ------------------------------------------------------------------
	// helper UI
	// ------------------------------------------------------------------
	function mkText(x:Float, y:Float, w:Float, txt:String, size:Int, color:FlxColor):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, txt, size);
		t.setFormat(Paths.font('vcr.ttf'), size, color, LEFT, OUTLINE_FAST, FlxColor.BLACK);
		t.borderSize = 1;
		t.scrollFactor.set();
		return t;
	}

	// ------------------------------------------------------------------
	// barra dei menu a tendina
	// ------------------------------------------------------------------
	function buildMenus()
	{
		inline function it(label:String, fn:Void->Void, keep:Bool = false)
			return {label: label, fn: fn, keep: keep};

		menus = [
			{
				name: 'File',
				items: [
					it('Inst file...', function() pick('ogg,wav', function(p) loadInstPath(p))),
					it('Songs >', nextSong, true),
					it('Open progetto...', function() project(false)),
					it('Save progetto...', function() project(true)),
					it('Export stems', function() exportAudio(true)),
					it('Export mix', function() exportAudio(false)),
					it('Close (ESC)', closeCover)
				]
			},
			{
				name: 'Import',
				items: [
					it('Dad MIDI...', function() importMidi(0)),
					it('BF MIDI...', function() importMidi(1)),
					it('Dad voice...', function() importVoice(0)),
					it('BF voice...', function() importVoice(1))
				]
			},
			{
				name: 'Play',
				items: [
					it('Play / Pause (SPACE)', togglePlay),
					it('Stop (ENTER)', stopAll),
					it('Page <', function() { page = Math.max(0, page - secondsPerPage); dirty = true; }, true),
					it('Page >', function() { page += secondsPerPage; dirty = true; }, true)
				]
			},
			{
				name: 'View',
				items: [
					it('Octave -', function() { low = Std.int(Math.max(0, low - 12)); dirty = true; }, true),
					it('Octave +', function() { low = Std.int(Math.min(104, low + 12)); dirty = true; }, true)
				]
			},
			{
				name: 'Voice',
				items: [
					it('Root -', function() changeRoot(-1), true),
					it('Root +', function() changeRoot(1), true),
					it('Threshold -', function() changeThreshold(-0.005), true),
					it('Threshold +', function() changeThreshold(0.005), true),
					it('Slide -', function() changeSlide(-1), true),
					it('Slide +', function() changeSlide(1), true),
					it('Mute track', function() { voices[track].muted = !voices[track].muted; refreshAudio(); dirty = true; }, true)
				]
			}
		];
	}

	inline function menuHeaderX(i:Int):Int
		return 10 + i * MENU_W;

	/** Indice del menu sotto il mouse nella barra, -1 se nessuno. */
	function headerAt(mx:Float, my:Float):Int
	{
		if (my < MENU_Y || my >= MENU_Y + MENU_H || mx < 10)
			return -1;
		var i:Int = Std.int((mx - 10) / MENU_W);
		return i < menus.length ? i : -1;
	}

	/** Indice della voce sotto il mouse nella tendina aperta, -1 se nessuna. */
	function itemAt(mx:Float, my:Float):Int
	{
		if (menuOpen < 0)
			return -1;
		var x:Int = menuHeaderX(menuOpen);
		var y:Int = MENU_Y + MENU_H + 2;
		var n:Int = menus[menuOpen].items.length;
		if (mx < x || mx >= x + MENU_ITEM_W || my < y || my >= y + n * MENU_ITEM_H)
			return -1;
		return Std.int((my - y) / MENU_ITEM_H);
	}

	function menuBox(x:Float, y:Float, w:Float, h:Float, c:Int)
	{
		rectTmp.setTo(x, y, w, h);
		menuLayer.pixels.fillRect(rectTmp, c);
	}

	function mlbl(x:Float, y:Float, s:String, color:Int)
	{
		if (mpoolIdx >= mpool.length)
			return;
		var t:FlxText = mpool[mpoolIdx++];
		t.x = x;
		t.y = y;
		if (t.text != s)
			t.text = s;
		t.color = color;
		t.visible = true;
	}

	function redrawMenu()
	{
		var bd = menuLayer.pixels;
		bd.lock();
		mpoolIdx = 0;
		menuBox(0, 0, FlxG.width, MENU_LAYER_H, 0x00000000);
		menuBox(0, MENU_Y, FlxG.width, MENU_H, 0xFF1B1E2C);

		for (i in 0...menus.length)
		{
			var x:Int = menuHeaderX(i);
			var on:Bool = menuOpen == i;
			if (on)
				menuBox(x, MENU_Y, MENU_W - 2, MENU_H, 0xFF3C4766);
			else if (menuHover == -2 - i)
				menuBox(x, MENU_Y, MENU_W - 2, MENU_H, 0xFF2B3248);
			mlbl(x + 8, MENU_Y + 4, menus[i].name, on ? 0xFFFFFFFF : 0xFFB8C0D8);
		}

		if (menuOpen >= 0)
		{
			var x:Int = menuHeaderX(menuOpen);
			var y:Int = MENU_Y + MENU_H + 2;
			var items = menus[menuOpen].items;
			menuBox(x - 1, y - 1, MENU_ITEM_W + 2, items.length * MENU_ITEM_H + 2, 0xFF7F88A8);
			menuBox(x, y, MENU_ITEM_W, items.length * MENU_ITEM_H, 0xFF20243A);
			for (j in 0...items.length)
			{
				if (menuHover == j)
					menuBox(x, y + j * MENU_ITEM_H, MENU_ITEM_W, MENU_ITEM_H, 0xFF3C4766);
				mlbl(x + 10, y + j * MENU_ITEM_H + 3, items[j].label, menuHover == j ? 0xFFFFFFFF : 0xFFD0D6EA);
			}
		}

		for (i in mpoolIdx...mpool.length)
			mpool[i].visible = false;
		bd.unlock();
		menuLayer.dirty = true;
	}

	function setMenu(open:Int, hover:Int)
	{
		if (open == menuOpen && hover == menuHover)
			return;
		menuOpen = open;
		menuHover = hover;
		redrawMenu();
	}

	/** Gestisce hover e click sui menu. Ritorna true se il click e' stato consumato. */
	function menuInput(mx:Float, my:Float):Bool
	{
		var h:Int = headerAt(mx, my);
		var ii:Int = itemAt(mx, my);

		// hover
		if (h >= 0)
			setMenu(menuOpen >= 0 ? h : menuOpen, -2 - h); // con tendina aperta, passare sopra un'altra voce la apre
		else
			setMenu(menuOpen, ii);

		if (FlxG.mouse.justPressedRight && menuOpen >= 0)
		{
			setMenu(-1, -1);
			return true;
		}
		if (!FlxG.mouse.justPressed)
			return false;

		if (h >= 0)
		{
			setMenu(menuOpen == h ? -1 : h, -2 - h);
			return true;
		}
		if (menuOpen >= 0)
		{
			if (ii >= 0)
			{
				var item = menus[menuOpen].items[ii];
				if (!item.keep)
					setMenu(-1, -1);
				try
					item.fn()
				catch (e:Dynamic)
					setStatus(Std.string(e));
			}
			else
				setMenu(-1, -1);
			return true;
		}
		return false;
	}

	function newSound():FlxSound
	{
		var s:FlxSound = new FlxSound();
		s.autoDestroy = false;
		FlxG.sound.list.add(s);
		return s;
	}

	function resetSnd(s:FlxSound)
	{
		s.stop();
		@:privateAccess s.cleanup(true);
	}

	inline function setStatus(s:String)
		statusText.text = s;

	function updateInfo()
	{
		var v:CoverVoice = voices[track];
		infoText.text = 'Traccia: ${track == 0 ? "Dad" : "BF"}${v.muted ? " [MUTE]" : ""}   voce: ${v.source == "" ? "(nessuna)" : v.source}   '
			+ 'fette: ${v.sliceCount()}   root: ${v.root}   soglia: ${Math.round(v.threshold * 1000) / 1000}   note: ${v.notes.length}   '
			+ 'BPM: ${Math.round(projectBpm * 100) / 100}';
	}

	function fmt(t:Float):String
	{
		var m:Int = Std.int(t / 60);
		var s:Float = t - m * 60;
		return m + ':' + (s < 10 ? '0' : '') + Std.string(Math.round(s * 100) / 100);
	}

	inline function pps():Float
		return (X1 - X0) / secondsPerPage;

	inline function mouseTime():Float
		return page + (FlxG.mouse.x - X0) / pps();

	inline function cur():CoverVoice
		return voices[track];

	function snap(t:Float):Float
		return Math.round(t / gridSec) * gridSec;

	function choose(i:Int)
	{
		track = i;
		selected = null;
		updateInfo();
		dirty = true;
	}

	function totalSeconds():Float
	{
		var end:Float = instLoaded ? instSnd.length / 1000 : 0;
		for (v in voices)
			for (n in v.notes)
				end = Math.max(end, v.offset + n.start + n.duration);
		return Math.max(0.1, end);
	}

	// ------------------------------------------------------------------
	// sorgenti
	// ------------------------------------------------------------------
	function pick(filter:String, fn:String->Void, mode:FileDialogType = OPEN)
	{
		dialog = new FileDialog();
		dialog.onSelect.add(function(p:String)
		{
			try
				fn(p)
			catch (e:Dynamic)
				setStatus(Std.string(e));
		});
		dialog.browse(mode, filter);
	}

	function setInst(s:Sound, path:String)
	{
		halt();
		resetSnd(instSnd);
		instSnd.loadEmbedded(s);
		instLoaded = true;
		instPath = path;
		renderDirty = [true, true];
		dirty = true;
	}

	function loadInstPath(p:String)
	{
		var s:Sound = Sound.fromFile(p);
		if (s == null)
			throw 'Audio non caricato: $p';
		setInst(s, p);
		setStatus('Instrumental: $p');
	}

	function scanSongs()
	{
		var roots:Array<String> = ['assets/songs', 'mods/songs'];
		if (FileSystem.exists('mods'))
			for (m in FileSystem.readDirectory('mods'))
				roots.push('mods/' + m + '/songs');
		for (r in roots)
			if (FileSystem.exists(r) && FileSystem.isDirectory(r))
				for (s in FileSystem.readDirectory(r))
					for (ext in ['ogg', 'wav'])
					{
						var p:String = r + '/' + s + '/Inst.' + ext;
						if (FileSystem.exists(p))
							catalog.push(p);
					}
		catalog.sort(Reflect.compare);
	}

	function nextSong()
	{
		if (catalog.length == 0)
			scanSongs();
		if (catalog.length == 0)
			throw 'Nessun Inst trovato in assets/songs o mods';
		songIndex = (songIndex + 1) % catalog.length;
		loadInstPath(catalog[songIndex]);
	}

	function importMidi(i:Int)
		pick('mid,midi', function(p)
		{
			var ns:Array<CoverNote> = CoverMidi.read(File.getBytes(p));
			choose(i);
			voices[i].notes = ns;
			if (ns.length > 0)
				low = Std.int(Math.min(104, Math.max(0, ns[0].pitch - 8)));
			edited(i);
			setStatus(ns.length + ' note importate per ' + (i == 0 ? 'Dad' : 'BF'));
		});

	function importVoice(i:Int)
		pick('wav,ogg', function(p)
		{
			voices[i].load(p);
			choose(i);
			edited(i);
			setStatus('Voce ' + (i == 0 ? 'Dad' : 'BF') + ': ' + p + ' (' + voices[i].sliceCount() + ' fette)');
		});

	function changeRoot(d:Int)
	{
		var v:CoverVoice = cur();
		v.root = Std.int(Math.max(0, Math.min(127, v.root + d)));
		edited(track);
	}

	function changeThreshold(d:Float)
	{
		var v:CoverVoice = cur();
		v.threshold = Math.max(0.001, Math.min(0.95, v.threshold + d));
		v.slice();
		edited(track);
	}

	function changeSlide(d:Int)
	{
		if (selected == null)
			return;
		selected.slide += d;
		edited(track);
		setStatus('Slide ' + selected.slide + ' semitoni sulla nota');
	}

	/** Da chiamare dopo ogni modifica che cambia l'audio della traccia. */
	function edited(i:Int)
	{
		renderDirty[i] = true;
		refreshAudio();
		updateInfo();
		dirty = true;
	}

	// ------------------------------------------------------------------
	// transport (il cursore segue il tempo dell'audio dell'Inst)
	// ------------------------------------------------------------------
	function currentTime():Float
		return (instLoaded && instSnd.playing) ? instSnd.time / 1000 : startedAt + (haxe.Timer.stamp() - started);

	function getRendered(i:Int, end:Float):Sound
	{
		var v:CoverVoice = voices[i];
		if (v.muted || v.source == '' || v.notes.length == 0)
			return null;
		if (rendered[i] == null || renderDirty[i] || renderedEnd[i] < end)
		{
			setStatus('Rendering ' + (i == 0 ? 'Dad' : 'BF') + '...');
			var buf:AudioBuffer = AudioBuffer.fromBytes(CoverVoice.wav(v.render(end)));
			if (buf == null)
				throw 'Decode del preview fallito';
			rendered[i] = Sound.fromAudioBuffer(buf);
			renderDirty[i] = false;
			renderedEnd[i] = end;
			setStatus('');
		}
		return rendered[i];
	}

	function play()
	{
		halt();
		var end:Float = totalSeconds();
		if (cursor >= end)
			cursor = 0;

		for (i in 0...2)
		{
			var s:Sound = getRendered(i, end);
			if (s == null)
				continue;
			resetSnd(voiceSnd[i]);
			voiceSnd[i].loadEmbedded(s);
			voiceSnd[i].volume = 1;
			if (cursor * 1000 < voiceSnd[i].length)
				voiceSnd[i].play(true, cursor * 1000);
		}
		if (instLoaded && cursor * 1000 < instSnd.length)
		{
			instSnd.volume = 1;
			instSnd.play(true, cursor * 1000);
		}
		startedAt = cursor;
		started = haxe.Timer.stamp();
		playing = true;
	}

	function halt()
	{
		if (playing)
			cursor = currentTime();
		playing = false;
		instSnd.pause();
		for (s in voiceSnd)
			s.pause();
	}

	function togglePlay()
	{
		if (playing)
			halt();
		else
		{
			origin = cursor;
			play();
		}
		dirty = true;
	}

	function stopAll()
	{
		halt();
		instSnd.stop();
		for (s in voiceSnd)
			s.stop();
		cursor = origin;
		dirty = true;
	}

	function refreshAudio()
	{
		if (playing)
		{
			halt();
			play();
		}
	}

	function seek(t:Float)
	{
		var resume:Bool = playing;
		halt();
		cursor = Math.max(0, t);
		origin = cursor;
		if (resume)
			play();
		dirty = true;
	}

	/** Anteprima di una singola nota mentre la modifichi. */
	function previewNote(n:CoverNote)
	{
		if (playing || n == null || cur().source == '')
			return;
		try
		{
			var buf:AudioBuffer = AudioBuffer.fromBytes(CoverVoice.wav(cur().preview(n)));
			if (buf == null)
				return;
			resetSnd(previewSnd);
			previewSnd.loadEmbedded(Sound.fromAudioBuffer(buf));
			previewSnd.volume = 1;
			previewSnd.play(true);
		}
		catch (e:Dynamic)
			trace('preview: $e');
	}

	/** Ogni oggetto aggiunto viene disegnato solo sulla camera del Cover Maker. */
	override public function add(basic:FlxBasic):FlxBasic
	{
		if (coverCam != null && basic != null)
			basic.cameras = [coverCam];
		return super.add(basic);
	}

	function restoreParent()
	{
		if (parentSaved && parentState != null)
		{
			parentState.persistentDraw = parentDraw;
			parentState.persistentUpdate = parentUpdate;
		}
		parentSaved = false;
	}

	function closeCover()
	{
		halt();
		restoreParent();
		close();
	}

	// ------------------------------------------------------------------
	// input
	// ------------------------------------------------------------------
	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (FlxG.keys.justPressed.ESCAPE)
		{
			if (menuOpen >= 0)
			{
				setMenu(-1, -1);
				return;
			}
			closeCover();
			return;
		}
		if (FlxG.keys.justPressed.SPACE)
			togglePlay();
		if (FlxG.keys.justPressed.ENTER)
			stopAll();
		if ((FlxG.keys.justPressed.DELETE || FlxG.keys.justPressed.BACKSPACE) && selected != null)
		{
			cur().notes.remove(selected);
			selected = null;
			edited(track);
		}

		if (playing)
		{
			cursor = currentTime();
			if (cursor >= totalSeconds())
			{
				halt();
				cursor = origin;
			}
			else if (cursor > page + secondsPerPage)
				page += secondsPerPage; // gira pagina
			dirty = true;
		}

		handleMouse();

		if (dirty)
		{
			redraw();
			dirty = false;
		}
	}

	function handleMouse()
	{
		var mx:Float = FlxG.mouse.x;
		var my:Float = FlxG.mouse.y;

		if (drag == '' && menuInput(mx, my))
			return;
		if (menuOpen >= 0 && drag == '')
		{
			if (FlxG.mouse.wheel != 0 || FlxG.mouse.justPressed || FlxG.mouse.justPressedRight)
				return;
		}

		if (FlxG.mouse.wheel != 0 && my >= RULER_Y)
		{
			if (FlxG.keys.pressed.CONTROL)
			{
				var anchor:Float = mouseTime();
				secondsPerPage = Math.max(1, Math.min(120, secondsPerPage * (1 - FlxG.mouse.wheel * 0.12)));
				page = Math.max(0, anchor - (mx - X0) / pps());
			}
			else if (FlxG.keys.pressed.SHIFT)
				low = Std.int(Math.max(0, Math.min(104, low + FlxG.mouse.wheel * 12)));
			else
				page = Math.max(0, page - FlxG.mouse.wheel * secondsPerPage * 0.1);
			dirty = true;
		}

		if (FlxG.mouse.justPressed)
			pressDown(mx, my);
		if (FlxG.mouse.justPressedRight)
			rightClick(mx, my);

		if (drag != '')
		{
			if (FlxG.mouse.pressed)
				dragMove();
			else
				endDrag();
		}
	}

	function inRoll(mx:Float, my:Float):Bool
		return mx >= X0 && my >= ROLL_Y && my < ROLL_Y + ROWS * ROW_H;

	function noteAt(mx:Float, my:Float):CoverNote
	{
		var v:CoverVoice = cur();
		var t:Float = page + (mx - X0) / pps();
		var p:Int = low + ROWS - 1 - Std.int((my - ROLL_Y) / ROW_H);
		var found:CoverNote = null;
		for (n in v.notes)
			if (n.pitch == p && t >= v.offset + n.start && t <= v.offset + n.start + n.duration)
				found = n;
		return found;
	}

	function pressDown(mx:Float, my:Float)
	{
		if (my < RULER_Y)
			return; // zona bottoni

		dragMx = mx;
		dragMy = my;
		var t:Float = page + (mx - X0) / pps();

		if (my < LANE_Y[0])
		{
			if (mx >= X0)
			{
				seek(t);
				drag = 'seek';
			}
		}
		else if (my >= LANE_Y[0] && my < LANE_Y[1] + LANE_H)
		{
			choose(my < LANE_Y[1] - 2 ? 0 : 1);
			if (mx >= X0)
			{
				drag = 'pattern';
				oldValue = cur().offset;
			}
		}
		else if (inRoll(mx, my))
		{
			var v:CoverVoice = cur();
			var p:Int = low + ROWS - 1 - Std.int((my - ROLL_Y) / ROW_H);
			selected = noteAt(mx, my);
			if (selected == null)
			{
				selected = {
					start: Math.max(0, snap(t - v.offset)),
					pitch: p,
					duration: gridSec,
					velocity: 100,
					channel: 0,
					slide: 0
				};
				v.notes.push(selected);
				drag = 'new';
			}
			else
			{
				var endX:Float = X0 + (v.offset + selected.start + selected.duration - page) * pps();
				drag = (endX - mx < 7) ? 'resize' : 'move';
			}
			oldValue = (drag == 'resize') ? selected.duration : selected.start;
			oldPitch = p;
			previewNote(selected);
			dirty = true;
		}
	}

	function rightClick(mx:Float, my:Float)
	{
		if (!inRoll(mx, my))
			return;
		var n:CoverNote = noteAt(mx, my);
		if (n != null)
		{
			cur().notes.remove(n);
			if (selected == n)
				selected = null;
			edited(track);
		}
	}

	function dragMove()
	{
		var d:Float = snap((FlxG.mouse.x - dragMx) / pps());
		switch (drag)
		{
			case 'seek':
				if (!playing)
				{
					cursor = Math.max(0, mouseTime());
					dirty = true;
				}
			case 'pattern':
				cur().offset = Math.max(0, oldValue + d);
				dirty = true;
			case 'resize':
				selected.duration = Math.max(gridSec, oldValue + d);
				dirty = true;
			case 'new', 'move':
				selected.start = Math.max(0, oldValue + d);
				var np:Int = Std.int(Math.max(0, Math.min(127, oldPitch - Math.round((FlxG.mouse.y - dragMy) / ROW_H))));
				if (np != selected.pitch)
				{
					selected.pitch = np;
					previewNote(selected);
				}
				dirty = true;
			default:
		}
	}

	function endDrag()
	{
		var d:String = drag;
		drag = '';
		if (d == 'seek')
			seek(mouseTime());
		else
			edited(track);
	}

	// ------------------------------------------------------------------
	// disegno: un solo bitmap, ridisegnato solo quando serve
	// ------------------------------------------------------------------
	function box(x:Float, y:Float, w:Float, h:Float, c:Int)
	{
		if (w <= 0 || h <= 0)
			return;
		rectTmp.setTo(x, y, w, h);
		canvas.pixels.fillRect(rectTmp, c);
	}

	/** Come box(), ma tagliato sull'area della timeline. */
	function cbox(x:Float, y:Float, w:Float, h:Float, c:Int)
	{
		var a:Float = Math.max(x, X0);
		var b:Float = Math.min(x + w, X1);
		if (b > a)
			box(a, y, b - a, h, c);
	}

	function lbl(x:Float, y:Float, s:String, color:Int = 0xFFFFFFFF)
	{
		if (poolIdx >= pool.length)
			return;
		var t:FlxText = pool[poolIdx++];
		t.x = x;
		t.y = y;
		if (t.text != s)
			t.text = s;
		t.color = color;
		t.visible = true;
	}

	function redraw()
	{
		var bd = canvas.pixels;
		bd.lock();
		poolIdx = 0;
		var pp:Float = pps();
		var bottom:Int = ROLL_Y + ROWS * ROW_H;

		box(0, 0, FlxG.width, FlxG.height, BG);

		// ---- sfondi ----
		box(X0, RULER_Y, X1 - X0, 22, 0xFF262A3C);
		cbox(X0, INST_Y, X1 - X0, 24, LANE_BG);
		lbl(6, INST_Y + 4, 'Inst', 0xFF8CB4FF);
		for (i in 0...2)
		{
			cbox(X0, LANE_Y[i], X1 - X0, LANE_H, track == i ? LANE_BG_ON : LANE_BG);
			lbl(6, LANE_Y[i] + 7, (i == 0 ? 'Dad' : 'BF') + (voices[i].muted ? ' [M]' : ''), TRACK_COLOR[i]);
		}

		var cv:CoverVoice = cur();
		var gapY:Int = INST_Y + 24 + 4;
		box(0, gapY, FlxG.width, ROLL_Y - gapY - 2, 0xFF262A3C);
		lbl(8, gapY + 1, 'PIANO ROLL - ' + (track == 0 ? 'Dad' : 'BF') + '   (clicca la corsia Dad o BF sopra per cambiare traccia)', TRACK_COLOR[track]);
		var sliceEnd:Int = cv.root + cv.sliceCount();
		for (i in 0...ROWS)
		{
			var p:Int = low + ROWS - 1 - i;
			var y:Int = ROLL_Y + i * ROW_H;
			var black:Bool = [1, 3, 6, 8, 10].indexOf(p % 12) >= 0;
			var inSlice:Bool = p >= cv.root && p < sliceEnd;
			cbox(X0, y, X1 - X0, ROW_H - 1, inSlice ? ROW_SLICE : (black ? ROW_DARK : ROW_LIGHT));
			box(0, y, X0 - 6, ROW_H - 1, black ? 0xFF15171E : 0xFFDDE1EC);
			if (p % 12 == 0)
				lbl(4, y, 'C' + Std.int(p / 12), 0xFF111111);
		}

		// ---- righello ----
		var step:Float = 60;
		for (c in [0.25, 0.5, 1, 2, 5, 10, 15, 30, 60])
			if (c * pp >= 70)
			{
				step = c;
				break;
			}
		var tt:Float = Math.ceil(page / step) * step;
		while (tt <= page + secondsPerPage)
		{
			var x:Float = X0 + (tt - page) * pp;
			box(x, RULER_Y + 10, 1, 12, 0xFF9AA0B8);
			lbl(x + 3, RULER_Y + 2, fmt(tt), 0xFFFFFFFF);
			tt += step;
		}

		// ---- griglia dei beat ----
		var beatSec:Float = 60 / projectBpm;
		if (beatSec * pp >= 8)
		{
			var b:Int = Std.int(Math.floor(page / beatSec));
			while (b * beatSec <= page + secondsPerPage)
			{
				var gx:Float = X0 + (b * beatSec - page) * pp;
				var gc:Int = (b % 4 == 0) ? 0xFF4A5170 : 0xFF2F3550;
				cbox(gx, LANE_Y[0], 1, INST_Y + 24 - LANE_Y[0], gc); // playlist
				cbox(gx, ROLL_Y, 1, bottom - ROLL_Y, gc); // piano roll
				b++;
			}
		}

		// ---- instrumental ----
		if (instLoaded)
			cbox(X0 + (0 - page) * pp, INST_Y + 5, instSnd.length / 1000 * pp, 14, 0xFF467B86);

		// ---- note nelle corsie Dad / BF ----
		for (i in 0...2)
		{
			var v:CoverVoice = voices[i];
			if (v.notes.length == 0)
				continue;
			var lo:Int = 127;
			var hi:Int = 0;
			var first:Float = 1e9;
			var last:Float = 0;
			for (n in v.notes)
			{
				lo = Std.int(Math.min(lo, n.pitch));
				hi = Std.int(Math.max(hi, n.pitch));
				first = Math.min(first, n.start);
				last = Math.max(last, n.start + n.duration);
			}
			var ly:Int = LANE_Y[i];
			cbox(X0 + (v.offset + first - page) * pp, ly, (last - first) * pp, 3, TRACK_COLOR[i]);
			var span:Float = Math.max(1, hi - lo);
			for (n in v.notes)
			{
				var ny:Float = ly + 6 + (hi - n.pitch) / span * (LANE_H - 11);
				cbox(X0 + (v.offset + n.start - page) * pp, ny, Math.max(2, n.duration * pp), 3, 0xFFFFFFFF);
			}
		}

		// ---- piano roll della traccia selezionata ----
		for (n in cv.notes)
		{
			if (n.pitch < low || n.pitch >= low + ROWS)
				continue;
			var ry:Int = ROLL_Y + (low + ROWS - 1 - n.pitch) * ROW_H;
			var nx:Float = X0 + (cv.offset + n.start - page) * pp;
			var nw:Float = Math.max(3, n.duration * pp);
			cbox(nx, ry, nw, ROW_H - 1, n == selected ? 0xFFFFCA66 : TRACK_COLOR[track]);
			if (n.slide != 0) // marcatore dello slide: dove arriva la nota alla fine
				cbox(nx + nw - 4, ry - n.slide * ROW_H, 4, ROW_H - 1, 0xFFFF8A3D);
		}

		// ---- cursore ----
		var cx:Float = X0 + (cursor - page) * pp;
		if (cx >= X0 && cx <= X1)
			{
				box(cx, RULER_Y, 2, INST_Y + 24 - RULER_Y, 0xFFFFFFFF);
				box(cx, ROLL_Y, 2, bottom - ROLL_Y, 0xFFFFFFFF);
			}

		for (i in poolIdx...pool.length)
			pool[i].visible = false;

		bd.unlock();
		canvas.dirty = true;
	}

	// ------------------------------------------------------------------
	// progetto ed export
	// ------------------------------------------------------------------
	function project(save:Bool)
	{
		if (save)
			pick('json', function(p)
			{
				File.saveContent(p, haxe.Json.stringify({
					song: songName,
					inst: instPath,
					tracks: [for (v in voices) {root: v.root, threshold: v.threshold, offset: v.offset, path: v.source, notes: v.notes, muted: v.muted}]
				}));
				setStatus('Progetto salvato');
			}, SAVE);
		else
			pick('json', function(p)
			{
				var data:Dynamic = haxe.Json.parse(File.getContent(p));
				var tracks:Array<Dynamic> = data.tracks;
				if (tracks.length != 2)
					throw 'Servono due tracce';
				var vs:Array<CoverVoice> = [];
				for (t in tracks)
				{
					var v:CoverVoice = new CoverVoice();
					v.root = t.root;
					v.threshold = t.threshold;
					if (t.path != '')
						v.load(t.path);
					v.offset = t.offset;
					v.notes = t.notes;
					v.muted = t.muted;
					vs.push(v);
				}
				var snd:Sound = (data.inst == '') ? Paths.inst(data.song) : Sound.fromFile(data.inst);
				halt();
				voices = vs;
				songName = data.song;
				setInst(snd, data.inst);
				rendered = [null, null];
				renderDirty = [true, true];
				cursor = page = 0;
				choose(0);
				setStatus('Progetto aperto');
			});
	}

	function exportAudio(split:Bool)
		pick('', function(dir)
		{
			var end:Float = totalSeconds();
			var a:Bytes = voices[0].render(end);
			var b:Bytes = voices[1].render(end);
			setStatus('Export in corso...');
			if (split)
			{
				saveWav(dir + '/Voices_Opponent.wav', a);
				saveWav(dir + '/Voices_Player.wav', b);
			}
			else
			{
				for (i in 0...Std.int(a.length / 2))
				{
					var j:Int = i * 2;
					var x:Int = a.getUInt16(j);
					var y:Int = b.getUInt16(j);
					var sum:Int = (x >= 32768 ? x - 65536 : x) + (y >= 32768 ? y - 65536 : y);
					a.setUInt16(j, Std.int(Math.max(-32768, Math.min(32767, sum))) & 65535);
				}
				saveWav(dir + '/Voices.wav', a);
			}
			setStatus('Esportato in ' + dir);
		}, OPEN_DIRECTORY);

	/** Scrive un WAV 16 bit mono 44.1 kHz. Nessun programma esterno. */
	function saveWav(path:String, b:Bytes)
		File.saveBytes(path, CoverVoice.wav(b));

	override function destroy()
	{
		restoreParent();
		for (s in [instSnd, previewSnd].concat(voiceSnd))
		{
			if (s == null)
				continue;
			s.stop();
			FlxG.sound.list.remove(s, true);
			s.destroy();
		}
		super.destroy();
		if (coverCam != null)
		{
			FlxG.cameras.remove(coverCam, true);
			coverCam = null;
		}
	}
}
#end
