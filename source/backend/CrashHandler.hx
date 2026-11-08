package backend;

import openfl.events.UncaughtErrorEvent;
import openfl.events.ErrorEvent;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.events.MouseEvent;
import openfl.errors.Error;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormatAlign;
import openfl.ui.Keyboard;
import flixel.FlxG;
import states.MainMenuState;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;
using flixel.util.FlxArrayUtil;

/**
 * Crash Handler.
 * @author Atox
 *
 * Modified: "null object reference" errors no longer crash the game.
 * A black screen with white text is shown instead; pressing OK sends the player to MainMenuState.
 */
class CrashHandler
{
	// Help link/repository to display in the event of a crash
	public static final HELP_LINK:String = "https://github.com/Psych-Plus-Team/FNF-PlusEngine";

	// ---- Null error screen state ----
	static var nullScreenActive:Bool = false;
	static var nullScreen:Sprite;
	static var nullText:TextField;
	static var nullButton:Sprite;

	/**
	 * Returns true if the message is a null object reference (or similar null access) error.
	 */
	static function isNullError(msg:String):Bool
	{
		if (msg == null)
			return false;

		var l = msg.toLowerCase();
		return l.contains("null object reference")
			|| l.contains("null function pointer")
			|| l.contains("null pointer");
	}

	public static function init():Void
	{
		openfl.Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);
		#if cpp
		untyped __global__.__hxcpp_set_critical_error_handler(onError);
		#elseif hl
		hl.Api.setErrorHandler(onError);
		#end
	}

	private static function onUncaughtError(e:UncaughtErrorEvent):Void
	{
		e.preventDefault();
		e.stopPropagation();
		e.stopImmediatePropagation();

		var m:String = e.error;
		if (Std.isOfType(e.error, Error))
		{
			var err = cast(e.error, Error);
			m = '${err.message}';
		}
		else if (Std.isOfType(e.error, ErrorEvent))
		{
			var err = cast(e.error, ErrorEvent);
			m = '${err.text}';
		}

		// A null error is already being shown: swallow repeated ones so the screen doesn't get spammed
		var nullError:Bool = isNullError(m);
		if (nullError && nullScreenActive)
			return;

		var stack = haxe.CallStack.exceptionStack();
		var stackLabelArr:Array<String> = [];
		var stackLabel:String = "";
		var firstSource:String = null; // first "File.hx line N" found in the stack
		for (e in stack)
		{
			switch (e)
			{
				case CFunction:
					stackLabelArr.push("Non-Haxe (C) Function");
				case Module(c):
					stackLabelArr.push('Module ${c}');
				case FilePos(parent, file, line, col):
					if (firstSource == null)
						firstSource = '${file} line ${line}';
					switch (parent)
					{
						case Method(cla, func):
							stackLabelArr.push('${file.replace('.hx', '')}.$func() [line $line]');
						case _:
							stackLabelArr.push('${file.replace('.hx', '')} [line $line]');
					}
				case LocalFunction(v):
					stackLabelArr.push('Local Function ${v}');
				case Method(cl, m):
					stackLabelArr.push('${cl} - ${m}');
			}
		}
		stackLabel = stackLabelArr.join('\r\n');

		var errorMsg = formatCrashText(nullError ? "Null Object Reference" : "Hardcoded Error", m, stackLabel, [
			"This crashed outside hxscript, so it is probably engine/source code or a compiled library path.",
			"Check the first source line in the stack before the engine loop; that is usually the useful culprit.",
			"If this only happens after editing scripts/classes, rebuild and make sure the exported assets are not stale."
		]);

		// Display the error in the console/terminal
		trace('\n\n$errorMsg');

		#if sys
		saveErrorMessage(errorMsg);
		#end

		// Null object reference: don't crash, show the black screen instead
		if (nullError)
		{
			showNullScreen(firstSource);
			return;
		}

		#if android
		showAndroidCrash(errorMsg, "Error!");
		#else
		CoolUtil.showPopUp(errorMsg, "Error!");
		#end
		#if DISCORD_ALLOWED DiscordClient.shutdown(); #end
		lime.system.System.exit(1);
	}

	// ------------------------------------------------------------------
	// Null error screen
	// ------------------------------------------------------------------

	private static function showNullScreen(where:String):Void
	{
		nullScreenActive = true;

		// Freeze the broken state and silence everything
		try
		{
			if (FlxG.state != null)
				FlxG.state.active = false;
		}
		catch (_:Dynamic) {}

		try
		{
			if (FlxG.sound != null)
			{
				if (FlxG.sound.music != null)
					FlxG.sound.music.stop();
				for (s in FlxG.sound.list)
					if (s != null)
						s.stop();
			}
		}
		catch (_:Dynamic) {}

		var stage = openfl.Lib.current.stage;

		nullScreen = new Sprite();

		// Text
		nullText = new TextField();
		var fmt = new TextFormat("_sans", 20, 0xFFFFFF);
		fmt.align = TextFormatAlign.CENTER;
		nullText.defaultTextFormat = fmt;
		nullText.selectable = false;
		nullText.mouseEnabled = false;
		nullText.multiline = true;
		nullText.wordWrap = true;
		nullText.autoSize = TextFieldAutoSize.LEFT;

		var body:String = "NULL OBJECT REFERENCE\n\n"
			+ "Something tried to use an object that doesn't exist (null).\n"
			+ "The game has been stopped to avoid a crash.\n";
		if (where != null)
			body += '\nWhere: $where\n';
		#if sys
		body += "\nA log was saved in the \"logs\" folder.\n";
		#end
		body += "\nPress OK to go back to the main menu.";
		nullText.text = body;
		nullScreen.addChild(nullText);

		// OK button
		nullButton = new Sprite();
		nullButton.graphics.lineStyle(2, 0xFFFFFF, 1);
		nullButton.graphics.beginFill(0x000000, 1);
		nullButton.graphics.drawRect(0, 0, 160, 48);
		nullButton.graphics.endFill();
		nullButton.buttonMode = true;

		var label = new TextField();
		var lfmt = new TextFormat("_sans", 24, 0xFFFFFF);
		lfmt.align = TextFormatAlign.CENTER;
		label.defaultTextFormat = lfmt;
		label.selectable = false;
		label.mouseEnabled = false;
		label.text = "OK";
		label.width = 160;
		label.height = 32;
		label.y = 8;
		nullButton.addChild(label);
		nullButton.addEventListener(MouseEvent.CLICK, onNullOkClick);
		nullScreen.addChild(nullButton);

		stage.addChild(nullScreen);
		stage.addEventListener(KeyboardEvent.KEY_DOWN, onNullKeyDown);
		stage.addEventListener(Event.RESIZE, onNullResize);

		layoutNullScreen();
	}

	private static function layoutNullScreen():Void
	{
		if (nullScreen == null)
			return;

		var stage = openfl.Lib.current.stage;
		var w:Float = stage.stageWidth;
		var h:Float = stage.stageHeight;

		nullScreen.graphics.clear();
		nullScreen.graphics.beginFill(0x000000, 1);
		nullScreen.graphics.drawRect(0, 0, w, h);
		nullScreen.graphics.endFill();

		nullText.width = w * 0.8;
		nullText.x = (w - nullText.width) / 2;

		var gap:Float = 30;
		var totalH:Float = nullText.height + gap + nullButton.height;
		nullText.y = Math.max(10, (h - totalH) / 2);

		nullButton.x = (w - nullButton.width) / 2;
		nullButton.y = nullText.y + nullText.height + gap;
	}

	private static function onNullResize(_:Event):Void
	{
		layoutNullScreen();
	}

	private static function onNullKeyDown(e:KeyboardEvent):Void
	{
		if (e.keyCode == Keyboard.ENTER || e.keyCode == Keyboard.SPACE || e.keyCode == Keyboard.ESCAPE)
			closeNullScreen();
	}

	private static function onNullOkClick(_:MouseEvent):Void
	{
		closeNullScreen();
	}

	private static function closeNullScreen():Void
	{
		if (!nullScreenActive)
			return;

		var stage = openfl.Lib.current.stage;
		stage.removeEventListener(KeyboardEvent.KEY_DOWN, onNullKeyDown);
		stage.removeEventListener(Event.RESIZE, onNullResize);

		if (nullButton != null)
			nullButton.removeEventListener(MouseEvent.CLICK, onNullOkClick);
		if (nullScreen != null && nullScreen.parent != null)
			nullScreen.parent.removeChild(nullScreen);

		nullScreen = null;
		nullText = null;
		nullButton = null;

		// Back to the main menu
		try
		{
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
		}
		catch (_:Dynamic) {}

		try
		{
			FlxG.switchState(new MainMenuState());
		}
		catch (err:Dynamic)
		{
			trace('Could not switch to MainMenuState: $err');
		}

		nullScreenActive = false;
	}

	// ------------------------------------------------------------------

	#if (cpp || hl)
	private static function onError(message:Dynamic):Void
	{
		var crashMessage:String = "Unknown critical error";
		if (message != null && message.length > 0)
			crashMessage = Std.string(message);

		var errorLog = formatCrashText("Critical Hardcoded Error", crashMessage, haxe.CallStack.toString(haxe.CallStack.exceptionStack(true)), [
			"This is a native/critical crash path, so the app could not recover cleanly.",
			"If this appeared during build testing, close every running PlusEngine.exe before rebuilding.",
			"If mods are enabled, retry with scripts disabled to separate engine crashes from mod-side crashes."
		]);

		// Display the error in the console/terminal
		trace('=== CRITICAL ERROR ===');
		trace(errorLog);
		trace('======================');
		trace('For help, visit: $HELP_LINK');

		#if sys
		saveErrorMessage(errorLog);
		#end

		#if android
		showAndroidCrash(errorLog, "Critical Error!");
		#else
		CoolUtil.showPopUp(errorLog, "Critical Error!");
		#end
		#if DISCORD_ALLOWED DiscordClient.shutdown(); #end
		lime.system.System.exit(1);
	}
	#end

	private static function formatCrashText(kind:String, message:String, stack:String, tips:Array<String>):String
	{
		var out:Array<String> = [];
		out.push('ERROR: $kind');
		out.push('');
		out.push('Message:');
		out.push(message == null || message.length < 1 ? 'Unknown error' : message);

		if (stack != null && stack.trim().length > 0)
		{
			out.push('');
			out.push('Trace:');
			out.push(stack);
		}

		if (tips != null && tips.length > 0)
		{
			out.push('');
			out.push('Tips:');
			for (tip in tips)
				out.push('- ' + tip);
		}

		out.push('');
		out.push('Need help? Visit:');
		out.push(HELP_LINK);
		return out.join('\n');
	}

	#if android
	private static function showAndroidCrash(message:String, title:String):Void
	{
		try
		{
			lime.system.JNI.createStaticMethod('org/haxe/lime/LimeCrashHandler', 'showHaxeCrash',
				'(Ljava/lang/String;Ljava/lang/String;)V', false, true)(title, message);
		}
		catch (e:Dynamic)
		{
			trace('Android crash activity dispatch failed: $e');
			CoolUtil.showPopUp(message, title);
		}
	}
	#end

	#if sys
	private static function saveErrorMessage(message:String):Void
	{
		final folder:String = #if android StorageUtil.getLogsDirectory() #else Sys.getCwd() + 'logs/' #end;

		try
		{
			if (!FileSystem.exists(folder))
				FileSystem.createDirectory(folder);

			var fullLog = message + '\n\n========================\nFor help, visit: $HELP_LINK\n========================';
			File.saveContent(folder + Date.now().toString().replace(' ', '-').replace(':', "'") + '.txt', fullLog);
		}
		catch (e:haxe.Exception)
			trace('Couldn\'t save error message. (${e.message})');
	}
	#end
}
