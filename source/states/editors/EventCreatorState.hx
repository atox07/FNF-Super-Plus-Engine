package states.editors;

import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.addons.transition.FlxTransitionableState;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import backend.Mods;
import backend.Paths;
import backend.ui.*;
import states.editors.FileDialogHandler;

/**
 * Event Creator — editor visuale per eventi custom di Super Plus Engine.
 *
 * Genera due file per evento:
 *   mods/<mod>/custom_events/<slug>.lua  -> codice (eseguito da PlayState)
 *   mods/<mod>/custom_events/<slug>.txt  -> descrizione (mostrata dal Chart Editor)
 *
 * Accesso previsto: Chart Editor -> File -> Custom Events...
 */
class EventCreatorState extends MusicBeatState implements PsychUIEventHandler.PsychUIEvent
{
	// ----------------------------------------------------------------
	// Dati del progetto (struttura "flat" come nel prototipo HTML)
	// ----------------------------------------------------------------
	public var projName:String = 'New Event';
	public var projDescription:String = '';
	public var projCategory:String = 'Visual';
	public var projChartValues:Int = 2;

	// Array di parametri e blocchi: saranno riempiti in Fase 2/3
	public var projParameters:Array<Dynamic> = [];
	public var projBlocks:Array<Dynamic> = [];

	// ----------------------------------------------------------------
	// UI
	// ----------------------------------------------------------------
	var camUI:FlxCamera;
	var bg:FlxSprite;
	var mainBox:PsychUIBox;
	var statusText:FlxText;
	var unsavedProgress:Bool = false;

	// Widget del tab Metadata
	var nameInput:PsychUIInputText;
	var descInput:PsychUIInputText;
	var categoryDD:PsychUIDropDownMenu;
	var chartValuesStepper:PsychUINumericStepper;
	var summaryText:FlxText;
	var fileNameText:FlxText;

	// Utility
	var fileDialog:FileDialogHandler;

	static inline var CATEGORIES:Array<String> = ['Visual', 'Audio', 'Camera', 'Gameplay', 'Other'];

	// ================================================================
	// CREATE / DESTROY
	// ================================================================
	override function create():Void
	{
		super.create();

		persistentUpdate = false;
		FlxG.mouse.visible = true;

		// Camera separata per la UI (come ChartingState)
		camUI = new FlxCamera();
		camUI.bgColor.alpha = 0;
		FlxG.cameras.add(camUI, false);

		// Background
		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.color = 0xFF1A1A2E;
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		bg.screenCenter();
		add(bg);

		// Status bar in basso (per i messaggi: "salvato", "errore", ecc.)
		statusText = new FlxText(0, FlxG.height - 30, FlxG.width, 'Ready.', 14);
		statusText.setFormat(Paths.font('vcr.ttf'), 14, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		statusText.scrollFactor.set();
		statusText.cameras = [camUI];
		add(statusText);

		// File dialog handler (per salvataggi avanzati, opzionale in futuro)
		fileDialog = new FileDialogHandler();

		// Main UI box con 4 tab
		mainBox = new PsychUIBox(FlxG.width * 0.5 - 250, 60, 500, 380, ['Metadata', 'Parameters', 'Actions', 'Code']);
		mainBox.selectedName = 'Metadata';
		mainBox.scrollFactor.set();
		mainBox.cameras = [camUI];
		mainBox.canMove = false;
		add(mainBox);

		setupMetadataTab();
		setupParametersTabPlaceholder();
		setupActionsTabPlaceholder();
		setupCodeTab();

		// Mostra subito il codice iniziale
		refreshCodePreview();
		refreshSummary();

		trace('[EventCreatorState] Ready. Active mod: "${Mods.currentModDirectory}"');
	}

	override function destroy():Void
	{
		if (fileDialog != null)
		{
			fileDialog.destroy();
			fileDialog = null;
		}
		super.destroy();
	}

	// ================================================================
	// TAB METADATA
	// ================================================================
	function setupMetadataTab():Void
	{
		var tab = mainBox.getTab('Metadata').menu;
		var objX:Float = 15;
		var objY:Float = 20;

		// Hint
		var hint = new FlxText(objX, objY, 460,
			'Define the event identity. The name appears in the Chart Editor dropdown; the category groups events in the palette.',
			12);
		hint.setFormat(Paths.font('vcr.ttf'), 12, 0xFFB0B0B0, LEFT);
		hint.wordWrap = true;
		tab.add(hint);
		objY += 45;

		// Name
		tab.add(makeLabel('Name (event ID):', objX, objY));
		nameInput = new PsychUIInputText(objX, objY + 18, 300, projName, 10);
		nameInput.onChange = function(_, cur:String)
		{
			projName = cur;
			unsavedProgress = true;
			refreshSummary();
			refreshCodePreview();
			setStatus('Modified.');
		};
		tab.add(nameInput);
		objY += 60;

		// Category
		tab.add(makeLabel('Category:', objX, objY));
		categoryDD = new PsychUIDropDownMenu(objX, objY + 18, CATEGORIES, function(_:Int, value:String)
		{
			projCategory = value;
			unsavedProgress = true;
			refreshSummary();
			refreshCodePreview();
			setStatus('Modified.');
		}, 200);
		categoryDD.selectedLabel = projCategory;
		tab.add(categoryDD);
		objY += 60;

		// Description
		tab.add(makeLabel('Description (shown in the Chart Editor):', objX, objY));
		descInput = new PsychUIInputText(objX, objY + 18, 460, projDescription, 10);
		descInput.onChange = function(_, cur:String)
		{
			projDescription = cur;
			unsavedProgress = true;
			refreshCodePreview();
			setStatus('Modified.');
		};
		tab.add(descInput);
		objY += 60;

		// Chart values
		tab.add(makeLabel('Values exposed in chart (1-8):', objX, objY));
		chartValuesStepper = new PsychUINumericStepper(objX, objY + 18, 1, projChartValues, 1, 8, 0, 80);
		chartValuesStepper.onValueChange = function()
		{
			projChartValues = Std.int(chartValuesStepper.value);
			unsavedProgress = true;
			refreshSummary();
			setStatus('Modified.');
		};
		tab.add(chartValuesStepper);
		objY += 60;

		// Summary box
		summaryText = new FlxText(objX, objY, 460, '', 13);
		summaryText.setFormat(Paths.font('vcr.ttf'), 13, 0xFFE0E0E0, LEFT);
		summaryText.wordWrap = true;
		tab.add(summaryText);
		objY += 50;

		// File name preview
		fileNameText = new FlxText(objX, objY, 460, '', 13);
		fileNameText.setFormat(Paths.font('vcr.ttf'), 13, 0xFF9FDFFF, LEFT);
		fileNameText.wordWrap = true;
		tab.add(fileNameText);
		objY += 40;

		// Save button
		var saveBtn = new PsychUIButton(objX, objY, 'Save to custom_events/', doSave, 200);
		saveBtn.normalStyle.bgColor = 0xFF2F8A2F;
		saveBtn.normalStyle.textColor = FlxColor.WHITE;
		saveBtn.onClick = doSave;
		tab.add(saveBtn);

		var closeBtn = new PsychUIButton(objX + 220, objY, 'Exit', requestExit, 100);
		closeBtn.normalStyle.bgColor = 0xFF8A2F2F;
		closeBtn.normalStyle.textColor = FlxColor.WHITE;
		closeBtn.onClick = requestExit;
		tab.add(closeBtn);
	}

	function makeLabel(text:String, x:Float, y:Float):FlxText
	{
		var t = new FlxText(x, y, 0, text, 12);
		t.setFormat(Paths.font('vcr.ttf'), 12, 0xFFA0A0FF, LEFT);
		return t;
	}

	// ================================================================
	// TAB PARAMETERS (placeholder — Fase 2)
	// ================================================================
	function setupParametersTabPlaceholder():Void
	{
		var tab = mainBox.getTab('Parameters').menu;
		var hint = new FlxText(15, 20, 460,
			'Parameters tab — coming in the next step.\n\nHere you will define what the event asks the charter for (name, type, default, min/max). The first N parameters (where N = chart values) are exposed as value1, value2, ... in the chart; the rest are fixed constants.',
			13);
		hint.setFormat(Paths.font('vcr.ttf'), 13, 0xFF909090, LEFT);
		hint.wordWrap = true;
		tab.add(hint);
	}

	// ================================================================
	// TAB ACTIONS (placeholder — Fase 3)
	// ================================================================
	function setupActionsTabPlaceholder():Void
	{
		var tab = mainBox.getTab('Actions').menu;
		var hint = new FlxText(15, 20, 460,
			'Actions tab — coming in a later step.\n\nHere you will add blocks from the palette (Play Sound, Tween Alpha, Change Character, ...). Blocks are executed top-to-bottom in onEvent().',
			13);
		hint.setFormat(Paths.font('vcr.ttf'), 13, 0xFF909090, LEFT);
		hint.wordWrap = true;
		tab.add(hint);
	}

	// ================================================================
	// TAB CODE (preview live)
	// ================================================================
	var codePreview:FlxText;

	function setupCodeTab():Void
	{
		var tab = mainBox.getTab('Code').menu;
		codePreview = new FlxText(10, 20, 480, '', 10);
		codePreview.setFormat('Consolas', 10, 0xFFE0E0E0, LEFT);
		codePreview.wordWrap = false;
		tab.add(codePreview);
	}

	function refreshCodePreview():Void
	{
		if (codePreview != null)
			codePreview.text = generateLuaCode();
	}

	// ================================================================
	// GENERAZIONE CODICE (versione Metadata-only)
	// ================================================================
	function slugify(s:String):String
	{
		var out = s.toLowerCase();
		out = StringTools.replace(out, 'à', 'a');
		out = StringTools.replace(out, 'è', 'e');
		out = StringTools.replace(out, 'é', 'e');
		out = StringTools.replace(out, 'ì', 'i');
		out = StringTools.replace(out, 'ò', 'o');
		out = StringTools.replace(out, 'ù', 'u');
		out = ~/[^a-z0-9]+/g.replace(out, '_');
		out = ~/^_+|_+$/g.replace(out, '');
		if (out.length < 1)
			out = 'event';
		if (~/^[0-9]/.test(out))
			out = 'e_' + out;
		return out;
	}

	function escapeLuaString(s:String):String
	{
		if (s == null)
			s = '';
		s = StringTools.replace(s, '\\', '\\\\');
		s = StringTools.replace(s, '"', '\\"');
		s = StringTools.replace(s, '\n', '\\n');
		s = StringTools.replace(s, '\r', '\\r');
		s = StringTools.replace(s, '\t', '\\t');
		return '"' + s + '"';
	}

	function generateLuaCode():String
	{
		var L:Array<String> = [];
		var slug = slugify(projName);

		L.push('-- ============================================================');
		L.push('--  ' + projName);
		L.push('--  Generated by Event Creator (Super Plus Engine)');
		L.push('--  You can edit this file by hand: it is normal Lua code.');
		L.push('-- ============================================================');
		L.push('');
		L.push('name = ' + escapeLuaString(projName));
		L.push('description = ' + escapeLuaString(projDescription));
		L.push('category = ' + escapeLuaString(projCategory));
		L.push('');
		L.push('-- Parameters (read by Event Creator and the Chart Editor)');
		L.push('parameters = {');
		if (projParameters.length < 1)
			L.push('    -- no parameters yet');
		L.push('}');
		L.push('');
		L.push('function onEvent(eventName, value1, value2, strumTime)');
		if (projBlocks.length < 1)
			L.push('    -- no actions yet');
		L.push('end');
		L.push('');
		return L.join('\n');
	}

	function generateDescriptionTxt():String
	{
		var desc = (projDescription != null && projDescription.length > 0) ? projDescription : projName;
		return '[' + projCategory + '] ' + desc;
	}

	// ================================================================
	// SUMMARY
	// ================================================================
	function refreshSummary():Void
	{
		if (summaryText == null)
			return;
		summaryText.text = 'Parameters: ' + projParameters.length
			+ '  |  Actions: ' + projBlocks.length
			+ '  |  Chart values: ' + projChartValues;

		if (fileNameText != null)
		{
			var slug = slugify(projName);
			fileNameText.text = 'File: mods/<active_mod>/custom_events/' + slug + '.lua\n'
				+ '      mods/<active_mod>/custom_events/' + slug + '.txt';
		}
	}

	// ================================================================
	// SALVATAGGIO
	// ================================================================
	function doSave():Void
	{
		var modDir = Mods.currentModDirectory;
		if (modDir == null || modDir.length < 1)
		{
			setStatus('ERROR: No active mod. Enable a mod first.', true);
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			return;
		}

		if (projName == null || projName.length < 1)
		{
			setStatus('ERROR: Event name is empty.', true);
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			return;
		}

		var slug = slugify(projName);
		var folder = 'mods/' + modDir + '/custom_events/';

		try
		{
			if (!FileSystem.exists(folder))
				FileSystem.createDirectory(folder);

			var luaPath = folder + slug + '.lua';
			var txtPath = folder + slug + '.txt';

			File.saveContent(luaPath, generateLuaCode());
			File.saveContent(txtPath, generateDescriptionTxt());

			unsavedProgress = false;
			setStatus('Saved to ' + luaPath + ' + .txt', false, 0xFF70D070);
			FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
			trace('[EventCreatorState] Saved: ' + luaPath + ' and ' + txtPath);
		}
		catch (e:Dynamic)
		{
			setStatus('ERROR saving: ' + Std.string(e), true);
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			trace('[EventCreatorState] Save failed: ' + Std.string(e));
		}
	}

	// ================================================================
	// EXIT
	// ================================================================
	function requestExit():Void
	{
		if (unsavedProgress)
		{
			openSubState(new states.editors.content.Prompt(
				'You have unsaved changes.\nExit anyway?',
				doExit
			));
		}
		else
			doExit();
	}

	function doExit():Void
	{
		// Torna al Chart Editor (che si ricrea da zero e ricarica il dropdown eventi)
		MusicBeatState.switchState(new ChartingState(false));
	}

	// ================================================================
	// UPDATE
	// ================================================================
	override function update(elapsed:Float):Void
	{
		ClientPrefs.toggleVolumeKeys(PsychUIInputText.focusOn == null);

		// ESC per uscire (solo se nessun input è focalizzato)
		if (PsychUIInputText.focusOn == null && FlxG.keys.justPressed.ESCAPE)
		{
			requestExit();
			return;
		}

		// Ctrl+S per salvare
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.S)
		{
			doSave();
			return;
		}

		super.update(elapsed);
	}

	// ================================================================
	// UIEvent (richiesto dall'interfaccia PsychUIEvent)
	// ================================================================
	public function UIEvent(id:String, sender:Dynamic):Void
	{
		// Per ora non facciamo nulla di speciale: i widget usano .onChange / .onClick
	}

	// ================================================================
	// UTILITY
	// ================================================================
	function setStatus(msg:String, isError:Bool = false, ?color:FlxColor):Void
	{
		if (statusText == null)
			return;
		statusText.text = msg;
		statusText.color = color != null ? color : (isError ? 0xFFFF6060 : FlxColor.WHITE);
	}
}
