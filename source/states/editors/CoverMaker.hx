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

	Layout: menu bar | ruler | Dad | BF | Inst | piano roll of the selected track.
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
	static inline var MENU_LAYER_H:Int = 420;

	// ---- slicer layout ----
	static inline var SL_TOP:Int = 118;
	static inline var TOOL_X:Int = 300;
	static inline var TOOL_W:Int = 144;
	static final SL_TOOLS:Array<String> = ['Manual: reset', 'Auto: transients', 'Auto: silence'];
	static inline var SL_RULER_Y:Int = 142;
	static inline var SL_WAVE_Y:Int = 164;
	static inline var SL_WAVE_H:Int = 340;
	static inline var SL_STRIP_Y:Int = 508;
	static inline var SL_STRIP_H:Int = 24;

	// ---- song list (File > Songs) ----
	static inline var SONG_ROWS:Int = 14;
	static inline var SONG_W:Int = 380;

	static final HINT_ROLL:String = 'SPACE play/pause | ENTER stop | TAB slicer | ESC close | DEL delete | click ruler = move cursor | drag Dad/BF lane = move pattern\n'
		+ 'Piano roll: click = new note, drag = move, right edge = resize, right click = delete | wheel = scroll, CTRL+wheel = zoom, ALT+wheel = pitch, SHIFT+wheel = octave\n'
		+ 'CTRL+Z undo | CTRL+Y redo | CTRL+left drag = select notes | drag selection = move | DEL = delete | SLIDE ON = draw a target over a sustained note';
	static final HINT_SLICER:String = 'SPACE play/pause | TAB back to piano roll | DEL delete slice | click slice = select + preview | SHIFT+click = cut here | drag a slice edge = resize\n'
		+ 'Right click = delete slice | wheel = scroll | CTRL+wheel = zoom | Ruler: click to add, drag to move, right-click a marker to merge\n'
		+ 'Every slice is a key: slice N plays on note (root + N). Highlighted rows in the piano roll show which keys have a slice.';

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
	var chartBpm:Float;
	static inline var BPM_X = 624;
	static inline var BPM_W = 152;
	static inline var GAIN_X = 44;
	static inline var GAIN_W = 66;
	var gainTrack:Int = 0;
	var gridSec:Float; // 1 step in secondi
	var voices:Array<CoverVoice> = [new CoverVoice(), new CoverVoice()]; // 0 = Dad (Opponent), 1 = BF (Player)
	var instPath:String = '';
	var instLoaded:Bool = false;
	var track:Int = 0;
	var selected:CoverNote = null;
	var group:haxe.ds.ObjectMap<CoverNote, Bool> = new haxe.ds.ObjectMap();
	var moving:Array<{note:CoverNote, start:Float, pitch:Int}> = [];
	var boxX:Float;
	var boxY:Float;
	var history:Array<{track:Int, before:String, after:String}> = [];
	var historyPos:Int = 0;
	var lastState:Array<String> = [];

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
	var hintText:FlxText;
	var slideMode:Bool = false;

	// ---- slicer state ----
	var slicerOpen:Bool = false;
	var slView0:Float = 0;
	var slSpan:Float = 2000;
	var slSel:Int = -1;

	// ---- song list state ----
	var songsOpen:Bool = false;
	var songScroll:Int = 0;
	var songHover:Int = -1;
	var parentState:FlxState;
	var parentDraw:Bool = true;
	var parentUpdate:Bool = false;
	var parentSaved:Bool = false;

	public function new(song:String, bpm:Float)
	{
		super();
		songName = song;
		chartBpm = Math.isFinite(bpm) && bpm > 0 ? bpm : 120;
		setTempo(chartBpm);
	}

	function setTempo(bpm:Float)
	{
		projectBpm = bpm;
		gridSec = 60 / projectBpm / 4;
	}

	function changeTempo(bpm:Float)
	{
		if (projectBpm == bpm) return;
		record(-2, Std.string(projectBpm), Std.string(bpm));
		setTempo(bpm);
		updateInfo();
		dirty = true;
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

		for (i in 0...160)
		{
			var t:FlxText = mkText(0, 0, 900, '', 12, FlxColor.WHITE);
			t.wordWrap = false;
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

		hintText = mkText(10, ROLL_Y + ROWS * ROW_H + 2, FlxG.width - 20, HINT_ROLL, 12, 0xFF7F88A8);
		hintText.wordWrap = true;
		add(hintText);

		// Barra dei menu: sempre sopra tutto il resto (overlay + testi propri)
		menuLayer = new FlxSprite(0, 0).makeGraphic(FlxG.width, MENU_LAYER_H, 0x00000000, true);
		menuLayer.scrollFactor.set();
		add(menuLayer);
		for (i in 0...44)
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

		resetHistory();
		setStatus('Load a MIDI and a voice for Dad and BF. Use the slicer ruler or Auto buttons to place markers.');
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
					it('Songs >', toggleSongs, true),
					it('Open project...', function() project(false)),
					it('Save project...', function() project(true)),
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
					it('Octave +', function() { low = Std.int(Math.min(104, low + 12)); dirty = true; }, true),
					it('Slicer on/off (TAB)', toggleSlicer)
				]
			},
			{
				name: 'Slicer',
				items: [
					it('Open / close (TAB)', toggleSlicer),
					it('Load WAV...', function() importVoice(track)),
					it('Switch track Dad/BF', function() choose(1 - track), true),
					it('Manual: reset markers', manualSlices),
					it('Detect: transients', runTransients, true),
					it('Detect: silence', runSilence, true),
					it('Sensitivity -', function() changeSens(-0.05), true),
					it('Sensitivity +', function() changeSens(0.05), true),
					it('Threshold -', function() changeThreshold(-0.005), true),
					it('Threshold +', function() changeThreshold(0.005), true),
					it('Preview slice', function() previewSlice(slSel), true),
					it('Delete slice (DEL)', deleteSlice, true),
					it('Merge with next slice', mergeSlice, true),
					it('Clear all slices', clearAllSlices, true)
				]
			},
			{
				name: 'Note',
				items: [
					it('Toggle slide', toggleSlide, true),
					it('Delete note (DEL)', deleteNote, true)
				]
			},
			{
				name: 'Voice',
				items: [
					it('Root -', function() changeRoot(-1), true),
					it('Root +', function() changeRoot(1), true),
					it('Mute track', function() { voices[track].muted = !voices[track].muted; edited(track); }, true)
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

	inline function slideX():Int
		return FlxG.width - 160;

	inline function songsX():Int
		return menuHeaderX(0) + MENU_ITEM_W + 4;

	inline function songsY():Int
		return MENU_Y + MENU_H + 2;

	function songRows():Int
		return Std.int(Math.max(0, Math.min(SONG_ROWS, catalog.length - songScroll)));

	function songAt(mx:Float, my:Float):Int
	{
		if (!songsOpen)
			return -1;
		var x:Int = songsX();
		var y:Int = songsY();
		if (mx < x || mx >= x + SONG_W || my < y || my >= y + songRows() * MENU_ITEM_H)
			return -1;
		return Std.int((my - y) / MENU_ITEM_H);
	}

	function inSongPanel(mx:Float, my:Float):Bool
	{
		if (!songsOpen)
			return false;
		var x:Int = songsX();
		var y:Int = songsY();
		return mx >= x && mx < x + SONG_W && my >= y && my < y + (songRows() + 1) * MENU_ITEM_H;
	}

	function songLabel(p:String):String
	{
		var parts:Array<String> = StringTools.replace(p, '\\', '/').split('/');
		var name:String = parts.length >= 2 ? parts[parts.length - 2] : p;
		var src:String = (parts[0] == 'mods' && parts.length > 4) ? parts[1] : parts[0];
		return name + '   (' + src + ')';
	}

	function toggleSongs()
	{
		if (catalog.length == 0)
			scanSongs();
		if (catalog.length == 0)
			throw 'No Inst found in assets/songs or mods';
		songsOpen = !songsOpen;
		var maxS:Int = Std.int(Math.max(0, catalog.length - SONG_ROWS));
		songScroll = Std.int(Math.max(0, Math.min(maxS, songIndex - 4)));
		redrawMenu();
	}

	function redrawMenu()
	{
		if (menuLayer == null)
			return;
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

		menuBox(BPM_X, MENU_Y + 1, BPM_W, MENU_H - 2, 0xFF2B3248);
		mlbl(BPM_X + 6, MENU_Y + 4, '-', 0xFFFFFFFF);
		mlbl(BPM_X + 27, MENU_Y + 4, 'BPM ' + (Math.round(projectBpm * 100) / 100), 0xFFFFFFFF);
		mlbl(BPM_X + BPM_W - 16, MENU_Y + 4, '+', 0xFFFFFFFF);

		var bx = slideX();
		menuBox(bx, MENU_Y + 1, 150, MENU_H - 2, slideMode ? 0xFFFF8A3D : 0xFF2B3248);
		mlbl(bx + 16, MENU_Y + 4, slideMode ? 'SLIDE: ON' : 'SLIDE: OFF', slideMode ? 0xFF111111 : 0xFFFFFFFF);

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

		if (songsOpen && menuOpen == 0)
		{
			var x:Int = songsX();
			var y:Int = songsY();
			var rows:Int = songRows();
			menuBox(x - 1, y - 1, SONG_W + 2, (rows + 1) * MENU_ITEM_H + 2, 0xFF7F88A8);
			menuBox(x, y, SONG_W, (rows + 1) * MENU_ITEM_H, 0xFF20243A);
			for (j in 0...rows)
			{
				var idx:Int = songScroll + j;
				if (songHover == j)
					menuBox(x, y + j * MENU_ITEM_H, SONG_W, MENU_ITEM_H, 0xFF3C4766);
				mlbl(x + 10, y + j * MENU_ITEM_H + 3, (idx == songIndex ? '> ' : '  ') + songLabel(catalog[idx]), songHover == j ? 0xFFFFFFFF : 0xFFD0D6EA);
			}
			if (catalog.length > SONG_ROWS)
				mlbl(x + 10, y + rows * MENU_ITEM_H + 3, 'wheel = scroll   (' + (songScroll + 1) + '-' + (songScroll + rows) + ' / ' + catalog.length + ')', 0xFF7F88A8);
			else
				mlbl(x + 10, y + rows * MENU_ITEM_H + 3, catalog.length + ' songs', 0xFF7F88A8);
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
		if (open != menuOpen)
		{
			songsOpen = false;
			songHover = -1;
		}
		menuOpen = open;
		menuHover = hover;
		redrawMenu();
	}

	/** Handles hover and clicks on the menu bar. Returns true if the click was consumed. */
	function menuInput(mx:Float, my:Float):Bool
	{
		var h:Int = headerAt(mx, my);
		var ii:Int = itemAt(mx, my);
		var si:Int = songAt(mx, my);

		// hover (with a dropdown open, moving over another header opens that one)
		if (h >= 0)
			setMenu(menuOpen >= 0 ? h : menuOpen, -2 - h);
		else
			setMenu(menuOpen, ii);
		if (si != songHover)
		{
			songHover = si;
			redrawMenu();
		}

		// wheel over the song list scrolls it
		if (songsOpen && FlxG.mouse.wheel != 0 && inSongPanel(mx, my))
		{
			var maxS:Int = Std.int(Math.max(0, catalog.length - SONG_ROWS));
			songScroll = Std.int(Math.max(0, Math.min(maxS, songScroll - FlxG.mouse.wheel * 2)));
			redrawMenu();
			return true;
		}

		if (FlxG.mouse.justPressedRight && menuOpen >= 0)
		{
			setMenu(-1, -1);
			return true;
		}
		if (!FlxG.mouse.justPressed)
			return false;

		if (my >= MENU_Y && my < MENU_Y + MENU_H && mx >= BPM_X && mx < BPM_X + BPM_W)
		{
			setMenu(-1, -1);
			var sign = mx < BPM_X + 24 ? -1 : (mx >= BPM_X + BPM_W - 24 ? 1 : 0);
			if (sign != 0)
			{
				var increment = FlxG.keys.pressed.SHIFT ? 10.0 : (FlxG.keys.pressed.CONTROL ? 0.1 : 1.0);
				changeTempo(Math.max(1, Math.min(999, Math.round((projectBpm + sign * increment) * 100) / 100)));
			}
			setStatus('BPM -/+ : 1   |   SHIFT: 10   |   CTRL: 0.1');
			return true;
		}

		if (my >= MENU_Y && my < MENU_Y + MENU_H && mx >= slideX() && mx < slideX() + 150)
		{
			setMenu(-1, -1);
			toggleSlide();
			return true;
		}

		// song list
		if (songsOpen && inSongPanel(mx, my))
		{
			if (si >= 0)
			{
				var idx:Int = songScroll + si;
				songIndex = idx;
				setMenu(-1, -1);
				try
					loadInstPath(catalog[idx])
				catch (e:Dynamic)
					setStatus(Std.string(e));
			}
			return true;
		}

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
		infoText.text = 'Track: ${track == 0 ? "Dad" : "BF"}${v.muted ? " [MUTE]" : ""}   voice: ${v.source == "" ? "(none)" : baseName(v.source)}   '
			+ 'slices: ${v.sliceCount()} (${v.mode})   root: ${v.root}   threshold: ${Math.round(v.threshold * 1000) / 1000}   notes: ${v.notes.length}   '
			+ 'BPM: ${Math.round(projectBpm * 100) / 100}';
		redrawMenu();
	}

	function baseName(p:String):String
	{
		var parts:Array<String> = StringTools.replace(p, '\\', '/').split('/');
		return parts[parts.length - 1];
	}

	function fixed(x:Float):String
		return Std.string(Math.round(x * 1000) / 1000);

	function noteName(p:Int):String
		return ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'][p % 12] + Std.int(p / 12);

	function fmt(t:Float):String
	{
		var m:Int = Std.int(t / 60);
		var s:Float = t - m * 60;
		return m + ':' + (s < 10 ? '0' : '') + Std.string(Math.round(s * 100) / 100);
	}

	inline function pps():Float
		return (X1 - X0) / secondsPerPage;

	inline function mouseTime():Float
		return page + (mouseX() - X0) / pps();

	inline function cur():CoverVoice
		return voices[track];

	// The song origin is shared by the grid and both tracks.
	function gridTime(time:Float, minimum:Float):Float
	{
		var first = Math.ceil(minimum / gridSec - 1e-9);
		return Math.max(first, Math.round(time / gridSec)) * gridSec;
	}

	inline function gridX(time:Float):Int
		return X0 + Math.round((time - page) * pps());

	function choose(i:Int)
	{
		track = i;
		clearSelection();
		slSel = -1;
		slicerFit();
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
			throw 'Audio not loaded: $p';
		var previous = instLoaded ? instPath : null;
		setInst(s, p);
		record(-1, previous, p);
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
			throw 'No Inst found in assets/songs or mods';
		songIndex = (songIndex + 1) % catalog.length;
		loadInstPath(catalog[songIndex]);
	}

	function importMidi(i:Int)
		pick('mid,midi', function(p)
		{
			var initialBpm = projectBpm;
			var ns:Array<CoverNote> = CoverMidi.read(File.getBytes(p), function(value) { initialBpm = value; });
			changeTempo(initialBpm);
			choose(i);
			voices[i].notes = ns;
			if (ns.length > 0)
				low = Std.int(Math.min(104, Math.max(0, ns[0].pitch - 8)));
			edited(i);
			setStatus(ns.length + ' notes imported for ' + (i == 0 ? 'Dad' : 'BF'));
		});

	function importVoice(i:Int)
		pick('wav,ogg', function(p)
		{
			voices[i].load(p, true);
			choose(i);
			slicerOpen = true; // show the freshly sliced sample right away
			updateHint();
			edited(i);
			setStatus('Voice ' + (i == 0 ? 'Dad' : 'BF') + ': ' + p + ' (click ruler to add markers, or choose Auto)');
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
		v.resliceAuto();
		if (v.mode != 'manual') slSel = -1;
		edited(track);
	}

	function toggleSlide()
	{
		slideMode = !slideMode;
		redrawMenu();
		setStatus(slideMode ? 'Draw a slide at the target pitch while the source note is sounding. Drag its right edge to set glide time.' : 'Draw normal notes.');
	}

	function deleteNote()
	{
		if (selected == null)
			return;
		cur().notes = [for (n in cur().notes) if (n != selected && !group.exists(n)) n];
		clearSelection();
		edited(track);
	}

	// ------------------------------------------------------------------
	// slicer
	// ------------------------------------------------------------------
	function toggleSlicer()
	{
		slicerOpen = !slicerOpen;
		slicerFit();
		updateHint();
		dirty = true;
	}

	function updateHint()
	{
		if (hintText != null)
			hintText.text = slicerOpen ? HINT_SLICER : HINT_ROLL;
	}

	function slicerFit()
	{
		slView0 = 0;
		slSpan = Math.max(2000, cur().sampleCount());
	}

	function slicerClamp()
	{
		var total:Float = Math.max(2000, cur().sampleCount());
		slSpan = Math.max(200, Math.min(total, slSpan));
		slView0 = Math.max(0, Math.min(total - slSpan, slView0));
	}

	inline function sx(x:Float):Float
		return slView0 + (x - X0) / (X1 - X0) * slSpan;

	inline function xs(smp:Float):Float
		return X0 + (smp - slView0) / slSpan * (X1 - X0);

	function needVoice():CoverVoice
	{
		var v:CoverVoice = cur();
		if (v.source == '')
			throw 'Load a WAV first (Slicer > Load WAV...)';
		return v;
	}

	function manualSlices()
	{
		var v = needVoice();
		v.resetMarkers();
		slSel = 0;
		edited(track);
		setStatus('Manual slicing: click the ruler to add a marker.');
	}

	function runTransients()
	{
		var v:CoverVoice = needVoice();
		v.detectTransients();
		slSel = -1;
		edited(track);
		setStatus('Transients: ' + v.sliceCount() + ' slices (sensitivity ' + fixed(v.sensitivity) + ')');
	}

	function runSilence()
	{
		var v:CoverVoice = needVoice();
		v.slice();
		slSel = -1;
		edited(track);
		setStatus('Silence: ' + v.sliceCount() + ' slices (threshold ' + fixed(v.threshold) + ')');
	}

	function changeSens(d:Float)
	{
		var v:CoverVoice = needVoice();
		v.sensitivity = Math.max(0.05, Math.min(1, v.sensitivity + d));
		if (v.mode == 'transient') runTransients();
		else edited(track);
	}

	function deleteSlice()
	{
		if (slSel < 0)
		{
			setStatus('Select a slice first');
			return;
		}
		cur().removeSlice(slSel);
		slSel = -1;
		edited(track);
	}

	function mergeSlice()
	{
		if (slSel < 0)
		{
			setStatus('Select a slice first');
			return;
		}
		cur().mergeNext(slSel);
		edited(track);
	}

	function clearAllSlices()
	{
		cur().clearSlices();
		slSel = -1;
		edited(track);
		setStatus('All slices removed (SHIFT+click on the waveform to cut new ones)');
	}

	function previewSlice(i:Int)
	{
		var v:CoverVoice = cur();
		if (playing || i < 0 || i >= v.sliceCount())
			return;
		try
			playBytes(v.previewSlice(i))
		catch (e:Dynamic)
			trace('preview: $e');
	}

	function inSlicerWave(mx:Float, my:Float):Bool
		return mx >= X0 && mx < X1 && my >= SL_WAVE_Y && my < SL_STRIP_Y + SL_STRIP_H;

	function slicerDown(mx:Float, my:Float)
	{
		var v:CoverVoice = cur();
		if (v.source != '' && my >= SL_TOP && my < SL_TOP + 21 && mx >= TOOL_X && mx < TOOL_X + TOOL_W * SL_TOOLS.length)
		{
			switch (Std.int((mx - TOOL_X) / TOOL_W))
			{
				case 0: manualSlices();
				case 1: runTransients();
				case 2: runSilence();
			}
			return;
		}
		if (v.source != '' && inMarkerRuler(mx, my))
		{
			var i = rulerMarker(mx);
			if (i >= 0)
			{
				slSel = i;
				dragMx = mx;
				drag = 'marker';
				dirty = true;
			}
			else
			{
				var added = v.splitAt(Std.int(sx(mx)));
				if (added >= 0) { slSel = added; edited(track); previewSlice(added); }
			}
			return;
		}
		if (v.source == '' || !inSlicerWave(mx, my))
			return;
		dragMx = mx;
		dragMy = my;

		// grab a slice edge?
		var best:Int = -1;
		var bestLeft:Bool = true;
		var bestD:Float = 7;
		for (i in 0...v.sliceCount())
		{
			var sl = v.getSlice(i);
			var da:Float = Math.abs(xs(sl.a) - mx);
			var db:Float = Math.abs(xs(sl.b) - mx);
			if (da < bestD)
			{
				bestD = da;
				best = i;
				bestLeft = true;
			}
			if (db < bestD)
			{
				bestD = db;
				best = i;
				bestLeft = false;
			}
		}
		if (best >= 0 && !FlxG.keys.pressed.SHIFT)
		{
			slSel = best;
			drag = bestLeft ? 'edgeL' : 'edgeR';
			dirty = true;
			return;
		}

		var smp:Int = Std.int(sx(mx));
		if (FlxG.keys.pressed.SHIFT)
		{
			var k:Int = v.splitAt(smp);
			if (k >= 0)
			{
				slSel = k;
				edited(track);
				previewSlice(k);
			}
			return;
		}
		slSel = v.sliceAt(smp);
		if (slSel >= 0)
			previewSlice(slSel);
		dirty = true;
	}

	function inMarkerRuler(mx:Float, my:Float):Bool
		return mx >= X0 && mx < X1 && my >= SL_RULER_Y && my < SL_WAVE_Y;

	function rulerMarker(mx:Float):Int
	{
		var best = -1;
		var distance:Float = 7;
		for (i in 0...cur().sliceCount())
		{
			var d = Math.abs(xs(cur().getSlice(i).a) - mx);
			if (d < distance) { distance = d; best = i; }
		}
		return best;
	}

	function slicerRight(mx:Float, my:Float)
	{
		var v:CoverVoice = cur();
		if (inMarkerRuler(mx, my))
		{
			var i = rulerMarker(mx);
			if (i > 0) { v.mergeNext(i - 1); slSel = i - 1; edited(track); }
			return;
		}
		if (v.source == '' || !inSlicerWave(mx, my))
			return;
		var i:Int = v.sliceAt(Std.int(sx(mx)));
		if (i >= 0)
		{
			v.removeSlice(i);
			slSel = -1;
			edited(track);
		}
	}

	function slicerWheel(mx:Float)
	{
		if (FlxG.keys.pressed.CONTROL)
		{
			var anchor:Float = sx(mx);
			slSpan = slSpan * (1 - FlxG.mouse.wheel * 0.15);
			slicerClamp();
			slView0 = anchor - (mx - X0) / (X1 - X0) * slSpan;
		}
		else
			slView0 -= FlxG.mouse.wheel * slSpan * 0.1;
		slicerClamp();
	}

	function drawSlicer()
	{
		var v:CoverVoice = cur();
		var W:Float = X1 - X0;
		var tn:String = track == 0 ? 'Dad' : 'BF';
		lbl(10, SL_TOP, 'SLICER - ' + tn + '   (TAB = back to piano roll)', TRACK_COLOR[track]);
		box(X0, SL_WAVE_Y, W, SL_WAVE_H, 0xFF1A1D2B);
		lbl(6, SL_WAVE_Y + SL_WAVE_H / 2 - 8, tn, TRACK_COLOR[track]);

		if (v.source == '' || v.sampleCount() == 0)
		{
			lbl(X0 + 20, SL_WAVE_Y + 20, 'No audio loaded.  Use  Slicer > Load WAV...  to import a sample and slice it.', 0xFFB8C0D8);
			return;
		}

		for (i in 0...SL_TOOLS.length)
		{
			var x = TOOL_X + i * TOOL_W;
			var active = (i == 0 && v.mode == 'manual') || (i == 1 && v.mode == 'transient') || (i == 2 && v.mode == 'silence');
			box(x, SL_TOP, TOOL_W - 3, 21, active ? 0xFF455E80 : 0xFF2B3248);
			lbl(x + 6, SL_TOP + 2, SL_TOOLS[i]);
		}
		var sr:Float = v.sampleRate();
		var n:Int = v.sliceCount();

		// time ruler
		box(X0, SL_RULER_Y, W, 20, 0xFF262A3C);
		var pxSec:Float = W / (slSpan / sr);
		var stepS:Float = 60;
		for (c in [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 30, 60])
			if (c * pxSec >= 70)
			{
				stepS = c;
				break;
			}
		var tt:Float = Math.ceil(slView0 / sr / stepS) * stepS;
		while (tt <= (slView0 + slSpan) / sr)
		{
			var tx:Float = xs(tt * sr);
			box(tx, SL_RULER_Y + 10, 1, 10, 0xFF9AA0B8);
			lbl(tx + 3, SL_RULER_Y + 2, fmt(tt), 0xFFFFFFFF);
			tt += stepS;
		}

		// slice regions + key strip
		for (i in 0...n)
		{
			var s = v.getSlice(i);
			var xa:Float = xs(s.a);
			var xb:Float = xs(s.b);
			if (xb < X0 || xa > X1)
				continue;
			cbox(xa, SL_WAVE_Y, xb - xa, SL_WAVE_H, i == slSel ? 0xFF3F5F8F : (i % 2 == 0 ? 0xFF262F4A : 0xFF2E3A5C));
			cbox(xa, SL_STRIP_Y, xb - xa - 1, SL_STRIP_H, i == slSel ? 0xFF5B7FB5 : 0xFF3A4C70);
			cbox(xa, SL_RULER_Y + 12, 7, 7, i == slSel ? 0xFFFFE08A : 0xFFFF8A3D);
			cbox(xa, SL_WAVE_Y, 2, SL_WAVE_H + SL_STRIP_H, 0xFFFF8A3D);
			cbox(xb - 1, SL_WAVE_Y, 1, SL_WAVE_H, 0xFF9A6B3D);
			if (xb - xa >= 30)
				lbl(Math.max(xa + 4, X0 + 2), SL_STRIP_Y + 4, (xb - xa >= 64) ? noteName(v.root + i) + '  #' + i : noteName(v.root + i), 0xFFFFFFFF);
		}

		// waveform (bright inside slices, dim outside)
		var cols:Int = Std.int(W);
		var pk:Array<Float> = v.waveform(slView0, slSpan, cols);
		var mid:Float = SL_WAVE_Y + SL_WAVE_H / 2;
		var amp:Float = SL_WAVE_H / 2 - 4;
		for (c in 0...cols)
		{
			var mn:Float = pk[c * 2];
			var mx:Float = pk[c * 2 + 1];
			if (mn == 0 && mx == 0)
				continue;
			var inside:Bool = v.sliceAt(Std.int(slView0 + (c + 0.5) / cols * slSpan)) >= 0;
			var y1:Float = mid - mx * amp;
			var y2:Float = mid - mn * amp;
			box(X0 + c, y1, 1, Math.max(1, y2 - y1), inside ? 0xFF9BD2E8 : 0xFF4A5570);
		}

		// details
		if (slSel >= 0 && slSel < n)
		{
			var s = v.getSlice(slSel);
			lbl(10, SL_STRIP_Y + 34, 'Slice #' + slSel + ' / ' + n + '   key: ' + noteName(v.root + slSel) + ' (MIDI ' + (v.root + slSel) + ')   start ' + fixed(s.a / sr) + 's   length ' + fixed((s.b - s.a) / sr) + 's', 0xFFFFE08A);
		}
		else
			lbl(10, SL_STRIP_Y + 34, 'No slice selected.  Root key: ' + noteName(v.root) + ' (MIDI ' + v.root + ')  -  slice N plays on key root + N.   ' + n + ' slices', 0xFFB8C0D8);
		lbl(10, SL_STRIP_Y + 56, 'Detection: ' + v.mode + '   sensitivity ' + fixed(v.sensitivity) + '   threshold ' + fixed(v.threshold) + '   root ' + v.root + '   (Slicer / Voice menus)', 0xFF8890B0);
	}

	function trackState(i:Int):String
	{
		var v = voices[i];
		return haxe.Json.stringify({path:v.source, notes:v.notes, root:v.root, threshold:v.threshold,
			offset:v.offset, muted:v.muted, gain:v.gain, sensitivity:v.sensitivity, mode:v.mode, slices:v.slicesAsArray()});
	}

	function resetHistory()
	{
		history = [];
		historyPos = 0;
		lastState = [trackState(0), trackState(1)];
	}

	function record(i:Int, before:String, after:String)
	{
		if (before == after) return;
		history.splice(historyPos, history.length - historyPos);
		history.push({track:i, before:before, after:after});
		if (history.length > 64) history.shift();
		historyPos = history.length;
	}

	function stepHistory(redo:Bool)
	{
		var index = redo ? historyPos : historyPos - 1;
		if (index < 0 || index >= history.length) return;
		var entry = history[index];
		var state = redo ? entry.after : entry.before;
		try
		{
			if (entry.track == -2)
			{
				setTempo(Std.parseFloat(state));
				updateInfo();
			}
			else if (entry.track < 0)
			{
				if (state == null)
				{
					halt();
					resetSnd(instSnd);
					instLoaded = false;
					instPath = '';
				}
				else
				{
					var sound = state == '' ? Paths.inst(songName) : Sound.fromFile(state);
					if (sound == null) throw 'Instrumental unavailable';
					setInst(sound, state);
				}
			}
			else
			{
				var t:Dynamic = haxe.Json.parse(state);
				var v = voices[entry.track];
				if (v.source != t.path)
				{
					v = new CoverVoice();
					if (t.path != '') v.load(t.path, true);
				}
				v.root = t.root;
				v.threshold = t.threshold;
				v.offset = t.offset;
				v.muted = t.muted;
				v.gain = t.gain == null ? 1.0 : Math.max(0, Math.min(4, t.gain));
				v.sensitivity = t.sensitivity;
				v.notes = t.notes;
				v.setSlices(t.slices);
				v.mode = t.mode;
				voices[entry.track] = v;
				lastState[entry.track] = state;
				choose(entry.track);
			}
			historyPos += redo ? 1 : -1;
			renderDirty = [true, true];
			refreshAudio();
			dirty = true;
			setStatus(redo ? 'Redo' : 'Undo');
		}
		catch (e:Dynamic) setStatus(Std.string(e));
	}

	/** Da chiamare dopo ogni modifica che cambia l'audio della traccia. */
	function edited(i:Int)
	{
		var state = trackState(i);
		record(i, lastState[i], state);
		lastState[i] = state;
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
				throw 'Preview decode failed';
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
			playBytes(cur().preview(n))
		catch (e:Dynamic)
			trace('preview: $e');
	}

	function playBytes(b:Bytes)
	{
		var buf:AudioBuffer = AudioBuffer.fromBytes(CoverVoice.wav(b));
		if (buf == null)
			return;
		resetSnd(previewSnd);
		previewSnd.loadEmbedded(Sound.fromAudioBuffer(buf));
		previewSnd.volume = 1;
		previewSnd.play(true);
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
		if (drag == '')
		{
			if (FlxG.keys.pressed.CONTROL && (FlxG.keys.justPressed.Z || FlxG.keys.justPressed.Y))
				stepHistory(FlxG.keys.justPressed.Y);
			else if (FlxG.keys.justPressed.TAB)
				toggleSlicer();
			else if (FlxG.keys.justPressed.DELETE || FlxG.keys.justPressed.BACKSPACE)
			{
				if (slicerOpen) deleteSlice(); else deleteNote();
			}
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
				page += secondsPerPage; // turn the page
			if (!slicerOpen)
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
		var mx:Float = mouseX();
		var my:Float = mouseY();

		if (drag == '' && menuInput(mx, my))
			return;
		if (menuOpen >= 0 && drag == '')
		{
			if (FlxG.mouse.wheel != 0 || FlxG.mouse.justPressed || FlxG.mouse.justPressedRight)
				return;
		}

		if (slicerOpen && FlxG.mouse.wheel != 0 && my >= RULER_Y)
		{
			slicerWheel(mx);
			dirty = true;
		}
		else if (FlxG.mouse.wheel != 0 && my >= RULER_Y)
		{
			if (FlxG.keys.pressed.ALT)
				low = Std.int(Math.max(0, Math.min(128 - ROWS, low + FlxG.mouse.wheel)));
			else if (FlxG.keys.pressed.CONTROL)
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
		{
			if (slicerOpen)
				slicerDown(mx, my);
			else
				pressDown(mx, my);
		}
		if (FlxG.mouse.justPressedRight)
		{
			if (slicerOpen)
				slicerRight(mx, my);
			else
				rightClick(mx, my);
		}

		if (drag != '')
		{
			if (FlxG.mouse.pressed)
				dragMove();
			else
				endDrag();
		}
	}

	/** Mouse position in screen space (the cover camera is fullscreen, unscrolled, zoom 1).
		FlxG.mouse.x/y would use the chart editor's camera (scroll/zoom) and be offset. */
	inline function mouseX():Float
		return FlxG.mouse.screenX;

	inline function mouseY():Float
		return FlxG.mouse.screenY;

	function inRoll(mx:Float, my:Float):Bool
		return mx >= X0 && mx < X1 && my >= ROLL_Y && my < ROLL_Y + ROWS * ROW_H;

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

	function clearSelection()
	{
		selected = null;
		group = new haxe.ds.ObjectMap();
		moving = [];
	}

	function updateBox()
	{
		boxX = Math.max(X0, Math.min(X1, mouseX()));
		boxY = Math.max(ROLL_Y, Math.min(ROLL_Y + ROWS * ROW_H, mouseY()));
		var left = Math.min(dragMx, boxX), right = Math.max(dragMx, boxX);
		var top = Math.min(dragMy, boxY), bottom = Math.max(dragMy, boxY);
		var pp = pps();
		clearSelection();
		for (n in cur().notes)
		{
			if (n.pitch < low || n.pitch >= low + ROWS) continue;
			var x = X0 + (cur().offset + n.start - page) * pp;
			var y = ROLL_Y + (low + ROWS - 1 - n.pitch) * ROW_H;
			if (x <= right && x + Math.max(3, n.duration * pp) > left && y <= bottom && y + ROW_H - 1 > top)
			{
				group.set(n, true);
				if (selected == null) selected = n;
			}
		}
		dirty = true;
	}

	function pressDown(mx:Float, my:Float)
	{
		if (my < RULER_Y)
			return; // menu bar area

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
			var lane = my < LANE_Y[1] - 2 ? 0 : 1;
			if (my >= LANE_Y[lane] && my < LANE_Y[lane] + LANE_H && mx >= GAIN_X - 3 && mx <= GAIN_X + GAIN_W + 3)
			{
				gainTrack = lane;
				drag = 'gain';
				return;
			}
			choose(lane);
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
			if (FlxG.keys.pressed.CONTROL)
			{
				drag = 'box';
				updateBox();
				return;
			}
			var hit = noteAt(mx, my);
			if (slideMode && hit != null && hit.slideTarget != true) hit = null;
			if (hit == null || !group.exists(hit)) clearSelection();
			selected = hit;
			if (selected == null)
			{
				selected = {
					start: Math.max(0, gridTime(t, v.offset) - v.offset),
					pitch: p,
					duration: gridSec,
					velocity: 127,
					channel: 0,
					slide: 0,
					slideTarget: slideMode
				};
				if (slideMode)
				{
					var source = v.sourceAt(selected.start);
					if (source != null) selected.channel = source.channel;
				}
				v.notes.push(selected);
				drag = 'new';
			}
			else
			{
				var endX:Float = X0 + (v.offset + selected.start + selected.duration - page) * pps();
				moving = [for (n in v.notes) if (group.exists(n)) {note:n, start:n.start, pitch:n.pitch}];
				drag = moving.length > 1 ? 'group' : ((endX - mx < 7) ? 'resize' : 'move');
			}
			oldValue = (drag == 'resize') ? selected.duration : selected.start;
			oldPitch = p;
			redrawMenu(); // SLIDE button shows the selected note
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
			group.remove(n);
			if (selected == n)
			{
				selected = null;
				for (remaining in group.keys()) { selected = remaining; break; }
			}
			edited(track);
		}
	}

	function dragMove()
	{
		var d:Float = (mouseX() - dragMx) / pps();
		var horizontal = Math.abs(mouseX() - dragMx) >= 2;
		switch (drag)
		{
			case 'seek':
				if (!playing)
				{
					cursor = Math.max(0, mouseTime());
					dirty = true;
				}
			case 'box':
				updateBox();
			case 'group':
				var pitchDelta = -Math.round((mouseY() - dragMy) / ROW_H);
				var earliest = oldValue;
				for (item in moving)
				{
					earliest = Math.min(earliest, item.start);
					pitchDelta = Std.int(Math.max(-item.pitch, Math.min(127 - item.pitch, pitchDelta)));
				}
				var anchor = cur().offset + oldValue;
				d = horizontal ? Math.max(-earliest, gridTime(anchor + d, anchor - earliest) - anchor) : 0;
				for (item in moving)
				{
					item.note.start = item.start + d;
					item.note.pitch = item.pitch + pitchDelta;
				}
				dirty = true;
			case 'gain':
				var percent = Math.round(Math.max(0, Math.min(1, (mouseX() - GAIN_X) / GAIN_W)) * 400);
				voices[gainTrack].gain = percent / 100.0;
				dirty = true;
			case 'pattern':
				cur().offset = horizontal ? gridTime(oldValue + d, 0) : oldValue;
				dirty = true;
			case 'marker':
				if (mouseX() != dragMx && slSel >= 0 && !(slSel == 0 && cur().getSlice(0).a == 0))
				{
					cur().setEdge(slSel, true, Std.int(sx(mouseX())));
					dragMx = mouseX();
					dirty = true;
				}
			case 'edgeL', 'edgeR':
				cur().setEdge(slSel, drag == 'edgeL', Std.int(sx(mouseX())));
				dirty = true;
			case 'resize':
				var start = cur().offset + selected.start;
				selected.duration = horizontal ? gridTime(start + oldValue + d, start + gridSec) - start : oldValue;
				dirty = true;
			case 'new', 'move':
				var offset = cur().offset;
				selected.start = horizontal ? Math.max(0, gridTime(offset + oldValue + d, offset) - offset) : oldValue;
				var np:Int = Std.int(Math.max(0, Math.min(127, oldPitch - Math.round((mouseY() - dragMy) / ROW_H))));
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
		moving = [];
		if (d == 'box')
		{
			updateBox();
			redrawMenu();
		}
		else if (d == 'gain')
			edited(gainTrack);
		else if (d == 'seek')
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

		if (slicerOpen)
		{
			drawSlicer();
			for (i in poolIdx...pool.length)
				pool[i].visible = false;
			bd.unlock();
			canvas.dirty = true;
			return;
		}

		// ---- backgrounds ----
		box(X0, RULER_Y, X1 - X0, 22, 0xFF262A3C);
		cbox(X0, INST_Y, X1 - X0, 24, LANE_BG);
		lbl(6, INST_Y + 4, 'Inst', 0xFF8CB4FF);
		for (i in 0...2)
		{
			cbox(X0, LANE_Y[i], X1 - X0, LANE_H, track == i ? LANE_BG_ON : LANE_BG);
			lbl(6, LANE_Y[i] + 7, (i == 0 ? 'Dad' : 'BF'), voices[i].muted ? 0xFF858595 : TRACK_COLOR[i]);
			var level = voices[i].gain;
			var y = LANE_Y[i] + 22;
			box(GAIN_X, y, GAIN_W + 1, 3, 0xFF384057);
			box(GAIN_X, y, GAIN_W * level / 4, 3, TRACK_COLOR[i]);
			box(GAIN_X + Math.round(GAIN_W * level / 4) - 2, y - 2, 4, 7, 0xFFDFE5ED);
			lbl(GAIN_X, LANE_Y[i] + 1, (voices[i].muted ? 'M ' : '') + Math.round(level * 100) + '%', TRACK_COLOR[i]);
		}

		var cv:CoverVoice = cur();
		var gapY:Int = INST_Y + 24 + 4;
		box(0, gapY, FlxG.width, ROLL_Y - gapY - 2, 0xFF262A3C);
		lbl(8, gapY + 1, 'PIANO ROLL - ' + (track == 0 ? 'Dad' : 'BF') + '   (click the Dad or BF lane above to switch track)', TRACK_COLOR[track]);
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

		// One step per sixteenth note. Skip subdivisions only when they cannot fit a pixel.
		var stride = 1;
		while (stride * gridSec * pp < 1) stride *= 2;
		var tick = Math.floor(page / (gridSec * stride)) * stride;
		var lastTick = Math.ceil((page + secondsPerPage) / gridSec);
		while (tick <= lastTick)
		{
			var gx = gridX(tick * gridSec);
			var beat = tick % 4 == 0;
			var color = tick % 16 == 0 ? 0xFF697596 : (beat ? 0xFF505B79 : 0xFF3E4862);
			if (beat) cbox(gx, LANE_Y[0], 1, INST_Y + 24 - LANE_Y[0], color);
			cbox(gx, ROLL_Y, 1, bottom - ROLL_Y, color);
			tick += stride;
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
			var start = cv.offset + n.start;
			var nx = gridX(start);
			var nw = Math.max(1, gridX(start + n.duration) - nx);
			cbox(nx, ry, nw, ROW_H - 1, (n == selected || group.exists(n)) ? 0xFFFFCA66 : ((n.slideTarget == true || n.slide != 0) ? 0xFFFF8A3D : TRACK_COLOR[track]));
			if (n.slideTarget == true)
			{
				var size = Std.int(Math.min(9, nw));
				for (i in 0...size) cbox(nx + i, ry + ROW_H - 2 - i, 1, i + 1, 0xFF54321E);
			}
			else if (n.slide != 0) // legacy slide: glide line up to the target pitch
			{
				var steps:Int = Std.int(Math.max(4, Math.min(80, nw / 3)));
				for (k in 0...steps + 1)
				{
					var f:Float = k / steps;
					var gy:Float = ry + ROW_H / 2 - n.slide * ROW_H * f;
					if (gy >= ROLL_Y && gy < bottom - 2)
						cbox(nx + f * nw, gy, 3, 2, 0xFFFFFFFF);
				}
			}
		}

		if (drag == 'box')
		{
			var x = Math.min(dragMx, boxX), y = Math.min(dragMy, boxY);
			var w = Math.max(1, Math.abs(boxX - dragMx)), h = Math.max(1, Math.abs(boxY - dragMy));
			box(x, y, w, 1, 0xFFFFCA66);
			box(x, y + h - 1, w, 1, 0xFFFFCA66);
			box(x, y, 1, h, 0xFFFFCA66);
			box(x + w - 1, y, 1, h, 0xFFFFCA66);
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
					bpm: projectBpm,
					inst: instPath,
					tracks: [for (v in voices) {root: v.root, threshold: v.threshold, offset: v.offset, path: v.source, notes: v.notes, muted: v.muted, gain: v.gain, sensitivity: v.sensitivity, mode: v.mode, slices: v.slicesAsArray()}]
				}));
				setStatus('Project saved');
			}, SAVE);
		else
			pick('json', function(p)
			{
				var data:Dynamic = haxe.Json.parse(File.getContent(p));
				var tracks:Array<Dynamic> = data.tracks;
				if (tracks.length != 2)
					throw 'Two tracks required';
				var vs:Array<CoverVoice> = [];
				for (t in tracks)
				{
					var v:CoverVoice = new CoverVoice();
					v.root = t.root;
					v.threshold = t.threshold;
					if (t.path != '')
					{
						v.load(t.path);
						if (t.sensitivity != null)
							v.sensitivity = t.sensitivity;
						if (t.slices != null)
						{
							v.setSlices(t.slices);
							if (t.mode != null)
								v.mode = t.mode;
						}
					}
					v.offset = t.offset;
					v.notes = t.notes;
					v.muted = t.muted;
					v.gain = t.gain == null ? 1.0 : Math.max(0, Math.min(4, t.gain));
					vs.push(v);
				}
				var snd:Sound = (data.inst == '') ? Paths.inst(data.song) : Sound.fromFile(data.inst);
				halt();
				voices = vs;
				songName = data.song;
				var bpm:Float = Std.parseFloat(Std.string(data.bpm));
				setTempo(Math.isFinite(bpm) && bpm > 0 ? bpm : chartBpm);
				setInst(snd, data.inst);
				rendered = [null, null];
				renderDirty = [true, true];
				cursor = page = 0;
				choose(0);
				resetHistory();
				setStatus('Project opened');
			});
	}

	function exportAudio(split:Bool)
		pick('', function(dir)
		{
			var end:Float = totalSeconds();
			var a:Bytes = voices[0].render(end);
			var b:Bytes = voices[1].render(end);
			setStatus('Exporting...');
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
			setStatus('Exported to ' + dir);
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
