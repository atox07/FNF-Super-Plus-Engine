package psychlua;

#if (LUA_ALLOWED && cpp && windows)
import openfl.display.BitmapData;
import openfl.geom.Matrix;
import openfl.geom.ColorTransform;
import lime.app.Application;
import psychlua.backend.FunkinLua;
import psychlua.backend.LuaUtils;

private class Attached
{
	public var spr:FlxSprite;
	public var offX:Float = 0;
	public var offY:Float = 0;
	public var hidden:Bool = false;
	/** true = forma vecchia: offX/offY = posizione (in pixel finestra) dell'angolo alto-sinistra dello sprite scalato */
	public var box:Bool = false;

	public function new(spr:FlxSprite, offX:Float, offY:Float, hidden:Bool, ?box:Bool = false)
	{
		this.box = box;
		this.spr = spr;
		this.offX = offX;
		this.offY = offY;
		this.hidden = hidden;
	}
}

private class WinInfo
{
	public var tag:String;
	public var id:Int;
	public var x:Int;
	public var y:Int;
	public var w:Int;
	public var h:Int;
	public var visible:Bool = true;
	public var viewX:Float = 0;
	public var viewY:Float = 0;
	public var zoom:Float = 1;
	public var bg:Int = 0x00000000;
	public var sprites:Array<Attached> = [];
	public var bmp:BitmapData = null;

	public function new(tag:String, id:Int, x:Int, y:Int, w:Int, h:Int)
	{
		this.tag = tag;
		this.id = id;
		this.x = x;
		this.y = y;
		this.w = w;
		this.h = h;
	}
}

/**
 * API Lua per aprire finestre Windows extra e mostrarci dentro sprite del gioco.
 * Gli sprite vengono ridisegnati nella finestra a ogni frame (postUpdate).
 */
class MultiWindowFunctions
{
	static var windows:Map<String, WinInfo> = new Map();
	static var hooked:Bool = false;
	static var exitHooked:Bool = false;

	// ------------------------------------------------------------ utilita'

	static function err(msg:String):Void
	{
		trace(msg);
		if (PlayState.instance != null)
			PlayState.instance.addTextToDebug(msg, FlxColor.RED);
	}

	static function getWin(tag:String, ?silent:Bool = false):WinInfo
	{
		var w = windows.get(tag);
		if (w == null && !silent)
			err('Finestra "$tag" non esiste (createWindow prima).');
		return w;
	}

	static function getSprite(name:String):FlxSprite
	{
		var split:Array<String> = name.split('.');
		var o:Dynamic = LuaUtils.getObjectDirectly(split[0]);
		if (split.length > 1)
			o = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1]);
		return (o != null && Std.isOfType(o, FlxSprite)) ? cast o : null;
	}

	static function num(v:Dynamic, def:Float):Float
	{
		if (v == null)
			return def;
		var f:Float = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? def : f;
	}

	static function parseColor(v:Dynamic):Int
	{
		if (Std.isOfType(v, String))
		{
			var c:Null<FlxColor> = FlxColor.fromString(cast v);
			return c == null ? 0 : (c : Int) & 0xFFFFFF;
		}
		return Std.int(v) & 0xFFFFFF;
	}

	// ------------------------------------------------------------ coordinate

	static inline function gw():lime.ui.Window
		return Application.current.window;

	/** coordinata X "di gioco" (0..1280, eventualmente dentro una camera) -> pixel dello schermo */
	public static function gameToScreenX(x:Float, ?cam:FlxCamera = null):Float
	{
		var px:Float = x;
		if (cam != null)
			px = cam.x + cam.width * 0.5 + (x - cam.width * 0.5) * cam.zoom;
		var sm = FlxG.scaleMode;
		return gw().x + sm.offset.x + px * sm.scale.x;
	}

	public static function gameToScreenY(y:Float, ?cam:FlxCamera = null):Float
	{
		var py:Float = y;
		if (cam != null)
			py = cam.y + cam.height * 0.5 + (y - cam.height * 0.5) * cam.zoom;
		var sm = FlxG.scaleMode;
		return gw().y + sm.offset.y + py * sm.scale.y;
	}

	static function spriteScreenPos(s:FlxSprite, cam:FlxCamera):{x:Float, y:Float}
	{
		var p = s.getScreenPosition(null, cam);
		var vx:Float = p.x - s.offset.x + s.origin.x * (1 - s.scale.x);
		var vy:Float = p.y - s.offset.y + s.origin.y * (1 - s.scale.y);
		p.put();
		return {x: gameToScreenX(vx, cam), y: gameToScreenY(vy, cam)};
	}

	// ------------------------------------------------------------ rendering

	static function drawSprite(win:WinInfo, a:Attached):Void
	{
		var s = a.spr;
		if (s == null || !s.exists || s.graphic == null || s.frame == null)
			return;
		if (s.alpha <= 0)
			return;
		// se lo sprite e' nascosto nel gioco, draw() non aggiorna il frame: lo facciamo noi
		var fp:BitmapData = s.updateFramePixels();
		if (fp == null)
			return;

		var m = new Matrix();
		if (a.box)
		{
			// posiziona il rettangolo scalato con l'angolo alto-sinistra in (offX, offY); rotazione attorno al centro
			var fw:Float = fp.width;
			var fh:Float = fp.height;
			var sw:Float = fw * s.scale.x;
			var sh:Float = fh * s.scale.y;
			m.translate(-fw * 0.5, -fh * 0.5);
			m.scale(s.scale.x, s.scale.y);
			if (s.angle != 0)
				m.rotate(s.angle * Math.PI / 180);
			m.translate(a.offX + sw * 0.5, a.offY + sh * 0.5);
		}
		else
		{
			var ox = s.origin.x;
			var oy = s.origin.y;
			m.translate(-ox, -oy);
			m.scale(s.scale.x, s.scale.y);
			if (s.angle != 0)
				m.rotate(s.angle * Math.PI / 180);
			m.translate(ox, oy);
			m.translate(s.x - s.offset.x + a.offX - win.viewX, s.y - s.offset.y + a.offY - win.viewY);
			m.scale(win.zoom, win.zoom);
		}

		var ct = new ColorTransform();
		ct.alphaMultiplier = s.alpha;
		var c:Int = s.color;
		if ((c & 0xFFFFFF) != 0xFFFFFF)
		{
			ct.redMultiplier = ((c >> 16) & 0xFF) / 255;
			ct.greenMultiplier = ((c >> 8) & 0xFF) / 255;
			ct.blueMultiplier = (c & 0xFF) / 255;
		}
		win.bmp.draw(fp, m, ct, s.blend, null, s.antialiasing);
	}

	static function renderWindow(win:WinInfo):Void
	{
		if (!win.visible)
			return;
		if (win.bmp == null || win.bmp.width != win.w || win.bmp.height != win.h)
		{
			if (win.bmp != null)
				win.bmp.dispose();
			win.bmp = new BitmapData(win.w, win.h, true, 0);
		}
		win.bmp.fillRect(win.bmp.rect, win.bg);

		var i = win.sprites.length;
		while (i-- > 0)
		{
			var a = win.sprites[i];
			if (a.spr == null || !a.spr.exists)
				win.sprites.splice(i, 1);
		}
		for (a in win.sprites)
			drawSprite(win, a);

		var bytes:haxe.io.Bytes = cast win.bmp.getPixels(win.bmp.rect);
		WinNative.present(win.id, bytes.getData(), win.w, win.h);
	}

	static function onFrame():Void
	{
		for (win in windows)
			renderWindow(win);
	}

	static function ensureHooks():Void
	{
		if (!hooked)
		{
			FlxG.signals.postUpdate.add(onFrame);
			hooked = true;
		}
		if (!exitHooked)
		{
			Application.current.onExit.add(function(_) closeAll());
			exitHooked = true;
		}
	}

	// ------------------------------------------------------------ chiusura

	static function closeInternal(win:WinInfo, showInGame:Bool):Void
	{
		for (a in win.sprites)
			if (showInGame && a.hidden && a.spr != null && a.spr.exists)
				a.spr.visible = true;
		win.sprites = [];
		WinNative.destroy(win.id);
		if (win.bmp != null)
		{
			win.bmp.dispose();
			win.bmp = null;
		}
	}

	/** Chiude tutte le finestre. Chiamata da PlayState.destroy() e all'uscita del gioco. */
	public static function closeAll():Void
	{
		for (win in windows)
			closeInternal(win, false);
		windows.clear();
		if (hooked)
		{
			FlxG.signals.postUpdate.remove(onFrame);
			hooked = false;
		}
	}

	// ------------------------------------------------------------ API Lua

	public static function implement(funk:FunkinLua)
	{
		var lua:State = funk.lua;

		Lua_helper.add_callback(lua, "createWindow", function(tag:String, ?title:String = "", ?x:Float = 0, ?y:Float = 0, ?w:Float = 400, ?h:Float = 400, ?borderless:Bool = true, ?transparent:Bool = true):Bool
		{
			if (windows.exists(tag))
				closeInternal(windows.get(tag), true);
			var iw = Std.int(Math.max(1, w));
			var ih = Std.int(Math.max(1, h));
			var id = WinNative.create(title, Std.int(x), Std.int(y), iw, ih);
			if (id == 0)
			{
				err('createWindow: impossibile creare la finestra "$tag".');
				windows.remove(tag);
				return false;
			}
			windows.set(tag, new WinInfo(tag, id, Std.int(x), Std.int(y), iw, ih));
			WinNative.setBorderless(id, borderless);
			WinNative.setTransparent(id, transparent);
			ensureHooks();
			return true;
		});

		Lua_helper.add_callback(lua, "closeWindow", function(tag:String, ?showInGame:Bool = true)
		{
			var win = getWin(tag);
			if (win == null)
				return;
			closeInternal(win, showInGame);
			windows.remove(tag);
		});
		Lua_helper.add_callback(lua, "closeAllWindows", function() closeAll());
		Lua_helper.add_callback(lua, "windowExists", function(tag:String) return windows.exists(tag));

		Lua_helper.add_callback(lua, "setWindowPos", function(tag:String, x:Float, y:Float)
		{
			var win = getWin(tag);
			if (win == null)
				return;
			win.x = Math.round(x);
			win.y = Math.round(y);
			WinNative.setPos(win.id, win.x, win.y);
		});
		Lua_helper.add_callback(lua, "setWindowSize", function(tag:String, w:Float, h:Float)
		{
			var win = getWin(tag);
			if (win == null)
				return;
			win.w = Std.int(Math.max(1, w));
			win.h = Std.int(Math.max(1, h));
			WinNative.setSize(win.id, win.w, win.h);
		});
		Lua_helper.add_callback(lua, "setWindowTitle", function(tag:String, title:String)
		{
			var win = getWin(tag);
			if (win != null)
				WinNative.setTitle(win.id, title);
		});
		Lua_helper.add_callback(lua, "setWindowBorderless", function(tag:String, v:Bool)
		{
			var win = getWin(tag);
			if (win != null)
				WinNative.setBorderless(win.id, v);
		});
		Lua_helper.add_callback(lua, "setWindowAlwaysOnTop", function(tag:String, v:Bool)
		{
			var win = getWin(tag);
			if (win != null)
				WinNative.setAlwaysOnTop(win.id, v);
		});
		Lua_helper.add_callback(lua, "setWindowTransparent", function(tag:String, v:Bool)
		{
			var win = getWin(tag);
			if (win != null)
				WinNative.setTransparent(win.id, v);
		});
		Lua_helper.add_callback(lua, "setWindowClickThrough", function(tag:String, v:Bool)
		{
			var win = getWin(tag);
			if (win != null)
				WinNative.setClickThrough(win.id, v);
		});
		Lua_helper.add_callback(lua, "setWindowVisible", function(tag:String, v:Bool)
		{
			var win = getWin(tag);
			if (win == null)
				return;
			win.visible = v;
			WinNative.setVisible(win.id, v);
		});
		// colore: "RRGGBB" / "#RRGGBB" / 0xRRGGBB. alpha 0..1 (0 = trasparente)
		Lua_helper.add_callback(lua, "setWindowBackground", function(tag:String, ?color:Dynamic = 0, ?alpha:Float = 1)
		{
			var win = getWin(tag);
			if (win == null)
				return;
			var a = Std.int(Math.max(0, Math.min(1, alpha)) * 255);
			win.bg = (a << 24) | parseColor(color);
		});

		// quale rettangolo del mondo di gioco si vede nella finestra (angolo alto-sinistra + zoom)
		Lua_helper.add_callback(lua, "setWindowView", function(tag:String, x:Float, y:Float, ?zoom:Float = 1)
		{
			var win = getWin(tag);
			if (win == null)
				return;
			win.viewX = x;
			win.viewY = y;
			win.zoom = zoom <= 0 ? 1 : zoom;
		});

		// Forma nuova:  addSpriteToWindow(winTag, obj, hideInGame, offX, offY)  -> sprite nel mondo, vista con setWindowView
		// Forma vecchia: addSpriteToWindow(spriteTag, winTag, offX, offY)        -> sprite messo a (offX, offY) nella finestra
		Lua_helper.add_callback(lua, "addSpriteToWindow", function(a1:String, a2:String, ?a3:Dynamic = null, ?a4:Dynamic = null, ?a5:Dynamic = null):Bool
		{
			var oldForm = !windows.exists(a1) && windows.exists(a2);
			var win = getWin(oldForm ? a2 : a1);
			if (win == null)
				return false;
			var objName = oldForm ? a1 : a2;
			var spr = getSprite(objName);
			if (spr == null)
			{
				err('addSpriteToWindow: "$objName" non e\' uno sprite.');
				return false;
			}
			for (a in win.sprites)
				if (a.spr == spr)
					return true;
			if (oldForm)
				win.sprites.push(new Attached(spr, num(a3, 0), num(a4, 0), false, true));
			else
			{
				var hide = a3 == null ? true : (a3 == true);
				if (hide)
					spr.visible = false;
				win.sprites.push(new Attached(spr, num(a4, 0), num(a5, 0), hide));
			}
			return true;
		});
		Lua_helper.add_callback(lua, "removeSpriteFromWindow", function(a1:String, a2:String, ?showInGame:Bool = true)
		{
			var oldForm = !windows.exists(a1) && windows.exists(a2);
			var win = getWin(oldForm ? a2 : a1);
			var spr = getSprite(oldForm ? a1 : a2);
			if (win == null || spr == null)
				return;
			for (a in win.sprites.copy())
				if (a.spr == spr)
				{
					if (showInGame && a.hidden)
						spr.visible = true;
					win.sprites.remove(a);
				}
		});

		// getter finestre extra
		Lua_helper.add_callback(lua, "getWindowX", function(tag:String) { var w = getWin(tag); return w == null ? 0 : w.x; });
		Lua_helper.add_callback(lua, "getWindowY", function(tag:String) { var w = getWin(tag); return w == null ? 0 : w.y; });
		Lua_helper.add_callback(lua, "getWindowWidth", function(tag:String) { var w = getWin(tag); return w == null ? 0 : w.w; });
		Lua_helper.add_callback(lua, "getWindowHeight", function(tag:String) { var w = getWin(tag); return w == null ? 0 : w.h; });

		// finestra del gioco e schermo
		Lua_helper.add_callback(lua, "getGameWindowX", function() return gw().x);
		Lua_helper.add_callback(lua, "getGameWindowY", function() return gw().y);
		Lua_helper.add_callback(lua, "getGameWindowWidth", function() return gw().width);
		Lua_helper.add_callback(lua, "getGameWindowHeight", function() return gw().height);
		Lua_helper.add_callback(lua, "getScreenWidth", function() return WinNative.screenWidth());
		Lua_helper.add_callback(lua, "getScreenHeight", function() return WinNative.screenHeight());

		// conversioni: camera = 'game' / 'hud' / 'other' oppure nil (coordinate stage grezze)
		Lua_helper.add_callback(lua, "gameToScreenX", function(x:Float, ?cam:String = null)
			return gameToScreenX(x, cam == null || cam == '' ? null : LuaUtils.cameraFromString(cam)));
		Lua_helper.add_callback(lua, "gameToScreenY", function(y:Float, ?cam:String = null)
			return gameToScreenY(y, cam == null || cam == '' ? null : LuaUtils.cameraFromString(cam)));

		// posizione/dimensione a schermo (pixel) di uno sprite del gioco
		Lua_helper.add_callback(lua, "getObjectScreenX", function(obj:String, ?cam:String = 'game'):Float
		{
			var s = getSprite(obj);
			return s == null ? 0.0 : spriteScreenPos(s, LuaUtils.cameraFromString(cam)).x;
		});
		Lua_helper.add_callback(lua, "getObjectScreenY", function(obj:String, ?cam:String = 'game'):Float
		{
			var s = getSprite(obj);
			return s == null ? 0.0 : spriteScreenPos(s, LuaUtils.cameraFromString(cam)).y;
		});
		Lua_helper.add_callback(lua, "getObjectScreenWidth", function(obj:String, ?cam:String = 'game'):Float
		{
			var s = getSprite(obj);
			if (s == null)
				return 0.0;
			return s.frameWidth * Math.abs(s.scale.x) * LuaUtils.cameraFromString(cam).zoom * FlxG.scaleMode.scale.x;
		});
		Lua_helper.add_callback(lua, "getObjectScreenHeight", function(obj:String, ?cam:String = 'game'):Float
		{
			var s = getSprite(obj);
			if (s == null)
				return 0.0;
			return s.frameHeight * Math.abs(s.scale.y) * LuaUtils.cameraFromString(cam).zoom * FlxG.scaleMode.scale.y;
		});
	}
}
#end
