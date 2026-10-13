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
import backend.ui.PsychUIEventHandler;
import states.editors.content.FileDialogHandler;
import states.editors.eventcreator.EventDef;
import states.editors.eventcreator.EventPalette;
import states.editors.eventcreator.EventPresets;
import states.editors.eventcreator.EventCodegen;

using StringTools;

/**
 * Event Creator — editor visuale per eventi custom di Super Plus Engine.
 *
 * Genera due file per evento (nome file = ID evento = nome nel Chart Editor):
 *   mods/<mod>/custom_events/<ID>.lua  -> codice (eseguito da PlayState)
 *   mods/<mod>/custom_events/<ID>.txt  -> descrizione (mostrata dal Chart Editor)
 * Senza mod attiva i file vanno in mods/custom_events/ (cartella globale).
 *
 * Tab: Metadata, Parameters, Actions, Code (anteprima live).
 * Accesso: Chart Editor -> File -> Custom Events...
 *
 * Regole PsychUI da ricordare (verificate sul sorgente dei widget):
 *  - Tutti i widget di una tab vanno creati in create(), prima del primo draw: il menu viene
 *    spostato ogni frame e un add() tardivo sposterebbe il widget di quell'offset.
 *  - Cambiare text/value/checked da codice NON scatena i callback (nessun loop).
 *  - visible=false non basta per nascondere un widget (i click passano): si usa exists=false.
 *  - PsychUIInputText registra un listener globale: i widget si creano una volta e si riusano.
 *  - Non sovrascrivere onChange/unfocus di un PsychUIDropDownMenu (li usa per filtrare).
 */
class EventCreatorState extends MusicBeatState implements PsychUIEventHandler.PsychUIEvent
{
	// ----------------------------------------------------------------
	// Costanti
	// ----------------------------------------------------------------
	static inline var BOX_W:Int = 900;
	static inline var BOX_H:Int = 560;
	static inline var MAX_PARAMS:Int = 12;
	static inline var MAX_BLOCKS:Int = 20;
	static inline var MAX_BLOCK_FIELDS:Int = 8;
	static inline var PALETTE_VISIBLE:Int = 12;
	static inline var PARAM_PICKER_VISIBLE:Int = 10;

	/** Righe di codice mostrate nel tab Code (il FlxText non scrolla ne' viene clippato). */
	static inline var CODE_PREVIEW_LINES:Int = 34;

	/** Origine x del pannello di dettaglio nel tab Parameters / Actions. */
	static inline var PX:Int = 275;

	/** Ease comuni (nomi accettati da LuaUtils.getTweenEaseByString). */
	static final EASE_OPTIONS:Array<String> = [
		'linear', 'quadIn', 'quadOut', 'quadInOut', 'cubeIn', 'cubeOut', 'cubeInOut',
		'quartIn', 'quartOut', 'quintIn', 'quintOut', 'sineIn', 'sineOut', 'sineInOut',
		'expoIn', 'expoOut', 'circIn', 'circOut', 'backIn', 'backOut', 'backInOut',
		'elasticOut', 'bounceOut', 'smoothStepInOut'
	];

	/** Target oggetti sempre presenti in PlayState. */
	static final OBJECT_OPTIONS:Array<String> = ['boyfriend', 'dad', 'gf'];

	// ----------------------------------------------------------------
	// Dati del progetto
	// ----------------------------------------------------------------
	public var project:EventProject = new EventProject();

	// ----------------------------------------------------------------
	// UI generale
	// ----------------------------------------------------------------
	var camUI:FlxCamera;
	var bg:FlxSprite;
	var mainBox:PsychUIBox;
	var statusText:FlxText;
	var unsavedProgress:Bool = false;

	/** Ultimo .lua scritto in questa sessione: salvarci di nuovo sopra non chiede conferma. */
	var lastSavedPath:String = null;

	// Tab Metadata
	var nameInput:PsychUIInputText;
	var descInput:PsychUIInputText;
	var categoryDD:PsychUIDropDownMenu;
	var chartValuesStepper:PsychUINumericStepper;
	var summaryText:FlxText;
	var fileNameText:FlxText;

	// Tab Parameters: colonna sinistra
	var selParam:Int = -1;
	var paramRows:Array<PsychUIButton> = [];
	var paramCountText:FlxText;

	// Tab Parameters: pannello di dettaglio (tutti creati una volta sola)
	var detailAll:Array<FlxSprite> = [];
	var pHintText:FlxText;
	var pInfoText:FlxText;
	var pVarText:FlxText;
	var pName:PsychUIInputText;
	var pTypeBtns:Array<PsychUIButton> = [];
	var pRangeCheck:PsychUICheckBox;
	var pMinLbl:FlxText;
	var pMaxLbl:FlxText;
	var pStepLbl:FlxText;
	var pMin:PsychUINumericStepper;
	var pMax:PsychUINumericStepper;
	var pStep:PsychUINumericStepper;
	var pOptionsLbl:FlxText;
	var pOptions:PsychUIInputText;
	var pPresetNote:FlxText;
	var pDefLbl:FlxText;
	var pDefText:PsychUIInputText;
	var pDefNum:PsychUINumericStepper;
	var pDefBool:PsychUICheckBox;
	var pDefColor:PsychUIInputText;
	var pDefSwatch:FlxSprite;
	var pDefDD:PsychUIDropDownMenu;

	// Tab Actions: colonna sinistra
	var selBlock:Int = -1;
	var actionRows:Array<PsychUIButton> = [];
	var actionToolbar:Array<PsychUIButton> = [];
	var actionCountText:FlxText;

	// Tab Actions: pannello di dettaglio
	var aHintText:FlxText;
	var aTitleText:FlxText;
	var aDescText:FlxText;
	var aPreviewText:FlxText;
	var aDetailAll:Array<FlxSprite> = [];
	var aFieldLbls:Array<FlxText> = [];
	var aFieldInputs:Array<PsychUIInputText> = [];
	var aFieldDDs:Array<PsychUIDropDownMenu> = [];
	var aFieldSwatches:Array<FlxSprite> = [];
	var aFieldBindBtns:Array<PsychUIButton> = [];
	/** Chiave del BlockFieldDef attualmente mappata su ogni slot (o null se vuoto). */
	var aFieldKeys:Array<String> = [];

	// Palette popup
	var paletteOpen:Bool = false;
	var paletteOverlay:FlxSprite;
	var palettePanel:FlxSprite;
	var paletteTitle:FlxText;
	var paletteSearch:PsychUIInputText;
	var paletteHint:FlxText;
	var paletteRows:Array<PsychUIButton> = [];
	var paletteScroll:Int = 0;
	var paletteFiltered:Array<BlockDef> = [];
	var paletteWidgets:Array<FlxSprite> = [];

	// Param picker popup
	var paramPickerOpen:Bool = false;
	var paramPickerOverlay:FlxSprite;
	var paramPickerPanel:FlxSprite;
	var paramPickerTitle:FlxText;
	var paramPickerRows:Array<PsychUIButton> = [];
	var paramPickerFieldIdx:Int = -1;
	var paramPickerWidgets:Array<FlxSprite> = [];

	// Tab Code
	var codePreview:FlxText;

	// Utility
	var fileDialog:FileDialogHandler;

	// ================================================================
	// CREATE / DESTROY
	// ================================================================
	override function create():Void
	{
		super.create();

		persistentUpdate = false;
		FlxG.mouse.visible = true;

		EventPalette.load();
		EventPresets.invalidate();

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

		// Status bar in basso
		statusText = new FlxText(0, FlxG.height - 30, FlxG.width, 'Ready.', 14);
		statusText.setFormat(Paths.font('vcr.ttf'), 14, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		statusText.scrollFactor.set();
		statusText.cameras = [camUI];
		add(statusText);

		fileDialog = new FileDialogHandler();

		// Finestra principale con 4 tab
		mainBox = new PsychUIBox(FlxG.width * 0.5 - BOX_W / 2, 40, BOX_W, BOX_H, ['Metadata', 'Parameters', 'Actions', 'Code']);
		mainBox.selectedName = 'Metadata';
		mainBox.scrollFactor.set();
		mainBox.cameras = [camUI];
		mainBox.canMove = false;
		add(mainBox);

		setupMetadataTab();
		setupParametersTab();
		setupActionsTab();
		setupCodeTab();

		refreshParamRows();
		loadParamIntoPanel();
		refreshActionRows();
		loadBlockIntoDetail();
		refreshCodePreview();
		refreshSummary();

		if (EventPalette.loadError != null)
			setStatus('Palette problem: ' + EventPalette.loadError, true);

		trace('[EventCreatorState] Ready. Active mod: "${Mods.currentModDirectory}", palette blocks: ${EventPalette.blocks.length}');
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

		var hint = new FlxText(objX, objY, BOX_W - 40,
			'Define the event identity. The name is the event ID: it appears in the Chart Editor dropdown and is the name of the saved files.',
			12);
		hint.setFormat(Paths.font('vcr.ttf'), 12, 0xFFB0B0B0, LEFT);
		hint.wordWrap = true;
		tab.add(hint);
		objY += 45;

		// Name
		tab.add(makeLabel('Name (event ID):', objX, objY));
		nameInput = new PsychUIInputText(objX, objY + 18, 300, project.name, 10);
		nameInput.onChange = function(_, cur:String)
		{
			project.name = cur;
			unsavedProgress = true;
			refreshSummary();
			refreshCodePreview();
			setStatus('Modified.');
		};
		tab.add(nameInput);
		objY += 60;

		// Category
		tab.add(makeLabel('Category:', objX, objY));
		categoryDD = new PsychUIDropDownMenu(objX, objY + 18, EventPalette.CATEGORIES, function(_:Int, value:String)
		{
			project.category = value;
			unsavedProgress = true;
			refreshSummary();
			refreshCodePreview();
			setStatus('Modified.');
		}, 200);
		categoryDD.selectedLabel = project.category;
		tab.add(categoryDD);
		objY += 60;

		// Description
		tab.add(makeLabel('Description (shown in the Chart Editor):', objX, objY));
		descInput = new PsychUIInputText(objX, objY + 18, BOX_W - 40, project.description, 10);
		descInput.onChange = function(_, cur:String)
		{
			project.description = cur;
			unsavedProgress = true;
			refreshCodePreview();
			setStatus('Modified.');
		};
		tab.add(descInput);
		objY += 60;

		// Quanti parametri finiscono nel chart (il formato chart ha solo value1 e value2)
		tab.add(makeLabel('Values exposed in chart (0-' + EventCodegen.MAX_CHART_VALUES + '):', objX, objY));
		chartValuesStepper = new PsychUINumericStepper(objX, objY + 18, 1, project.chartValues, 0, EventCodegen.MAX_CHART_VALUES, 0, 80);
		chartValuesStepper.onValueChange = function()
		{
			project.chartValues = Std.int(chartValuesStepper.value);
			unsavedProgress = true;
			refreshSummary();
			refreshParamRows();
			updateParamInfo();
			refreshCodePreview();
			setStatus('Modified.');
		};
		tab.add(chartValuesStepper);
		objY += 60;

		summaryText = new FlxText(objX, objY, BOX_W - 40, '', 13);
		summaryText.setFormat(Paths.font('vcr.ttf'), 13, 0xFFE0E0E0, LEFT);
		summaryText.wordWrap = true;
		tab.add(summaryText);
		objY += 30;

		fileNameText = new FlxText(objX, objY, BOX_W - 40, '', 13);
		fileNameText.setFormat(Paths.font('vcr.ttf'), 13, 0xFF9FDFFF, LEFT);
		fileNameText.wordWrap = true;
		tab.add(fileNameText);
		objY += 45;

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

		var sampleBtn = new PsychUIButton(objX + 340, objY, 'Load example (Glitch Effect)', loadSample, 220);
		sampleBtn.onClick = loadSample;
		tab.add(sampleBtn);
	}

	function makeLabel(text:String, x:Float, y:Float):FlxText
	{
		var t = new FlxText(x, y, 0, text, 12);
		t.setFormat(Paths.font('vcr.ttf'), 12, 0xFFA0A0FF, LEFT);
		return t;
	}

	// ================================================================
	// TAB PARAMETERS  (lista a sinistra, editor del parametro selezionato a destra)
	// ================================================================
	function setupParametersTab():Void
	{
		var tab = mainBox.getTab('Parameters').menu;

		// ---------------- colonna sinistra: lista ----------------
		tab.add(makeLabel('Parameters:', 15, 20));
		for (i in 0...MAX_PARAMS)
		{
			var idx:Int = i;
			var row = new PsychUIButton(15, 38 + i * 22, '', function() selectParam(idx), 240, 20);
			paramRows.push(row);
			tab.add(row);
		}

		var by:Int = 38 + MAX_PARAMS * 22 + 8;
		tab.add(new PsychUIButton(15, by, '+ Add', addParam, 70));
		tab.add(new PsychUIButton(90, by, 'Delete', deleteParam, 70));
		tab.add(new PsychUIButton(165, by, 'Up', function() moveParam(-1), 45));
		tab.add(new PsychUIButton(215, by, 'Down', function() moveParam(1), 45));
		tab.add(new PsychUIButton(15, by + 26, 'Toggle: chart / fixed', toggleFixed, 245));

		paramCountText = new FlxText(15, by + 56, 245, '', 10);
		paramCountText.setFormat(Paths.font('vcr.ttf'), 10, 0xFF909090, LEFT);
		paramCountText.wordWrap = true;
		tab.add(paramCountText);

		// ---------------- pannello di dettaglio ----------------
		pHintText = new FlxText(PX, 20, 590,
			'Parameters are what the event asks the charter for.\n\n'
			+ 'The first N non-fixed parameters (N = "Values exposed in chart") become value1 / value2 in the chart. '
			+ 'Fixed ones, and any beyond the first two, are constants written in the Lua file.\n\n'
			+ 'Press "+ Add" to create the first parameter.',
			12);
		pHintText.setFormat(Paths.font('vcr.ttf'), 12, 0xFF909090, LEFT);
		pHintText.wordWrap = true;
		tab.add(pHintText);

		// Name
		var lblName = makeLabel('Name:', PX, 20);
		detailAll.push(lblName);
		tab.add(lblName);

		pName = new PsychUIInputText(PX, 38, 300, '', 10);
		pName.onChange = function(_, cur:String)
		{
			var p = curParam();
			if (p == null)
				return;
			p.name = cur;
			paramChanged();
		};
		detailAll.push(pName);
		tab.add(pName);

		pVarText = new FlxText(PX + 320, 40, 270, '', 11);
		pVarText.setFormat(Paths.font('vcr.ttf'), 11, 0xFF9FDFFF, LEFT);
		detailAll.push(pVarText);
		tab.add(pVarText);

		// Type (11 bottoni su due righe: niente dropdown, cosi' non coprono altri widget)
		var lblType = makeLabel('Type:', PX, 70);
		detailAll.push(lblType);
		tab.add(lblType);
		for (i in 0...ParamTypes.ALL.length)
		{
			var t:String = ParamTypes.ALL[i];
			var col:Int = (i < 6) ? i : i - 6;
			var rowY:Int = (i < 6) ? 88 : 112;
			var b = new PsychUIButton(PX + col * 70, rowY, ParamTypes.LABELS[i], function() setParamType(t), 66, 20);
			pTypeBtns.push(b);
			detailAll.push(b);
			tab.add(b);
		}

		// Range (int/float: opzionale; slider: sempre)
		pRangeCheck = new PsychUICheckBox(PX, 148, 'Limit to a min / max range', 260);
		pRangeCheck.onClick = function()
		{
			var p = curParam();
			if (p == null)
				return;
			p.useRange = pRangeCheck.checked;
			loadParamIntoPanel();
			paramChanged();
		};
		detailAll.push(pRangeCheck);
		tab.add(pRangeCheck);

		pMinLbl = makeLabel('Min', PX, 172);
		pMaxLbl = makeLabel('Max', PX + 140, 172);
		pStepLbl = makeLabel('Step', PX + 280, 172);
		for (l in [pMinLbl, pMaxLbl, pStepLbl])
		{
			detailAll.push(l);
			tab.add(l);
		}

		pMin = new PsychUINumericStepper(PX, 190, 1, 0, -99999, 99999, 3, 90);
		pMin.onValueChange = function()
		{
			var p = curParam();
			if (p == null)
				return;
			p.min = pMin.value;
			if (p.max < p.min)
			{
				p.max = p.min;
				pMax.value = p.max;
			}
			configDefStepper(p);
			paramChanged();
		};
		pMax = new PsychUINumericStepper(PX + 140, 190, 1, 1, -99999, 99999, 3, 90);
		pMax.onValueChange = function()
		{
			var p = curParam();
			if (p == null)
				return;
			p.max = pMax.value;
			if (p.min > p.max)
			{
				p.min = p.max;
				pMin.value = p.min;
			}
			configDefStepper(p);
			paramChanged();
		};
		pStep = new PsychUINumericStepper(PX + 280, 190, 0.01, 0.05, 0.001, 100, 3, 90);
		pStep.onValueChange = function()
		{
			var p = curParam();
			if (p == null)
				return;
			p.step = pStep.value;
			configDefStepper(p);
			paramChanged();
		};
		for (s in [pMin, pMax, pStep])
		{
			detailAll.push(s);
			tab.add(s);
		}

		// Options (solo tipo List)
		pOptionsLbl = makeLabel('Options (comma separated):', PX, 150);
		detailAll.push(pOptionsLbl);
		tab.add(pOptionsLbl);
		pOptions = new PsychUIInputText(PX, 168, 590, '', 10);
		pOptions.onChange = function(_, cur:String)
		{
			var p = curParam();
			if (p == null)
				return;
			p.options = parseOptions(cur);
			refreshDefaultDropdown(p);
			paramChanged();
		};
		detailAll.push(pOptions);
		tab.add(pOptions);

		// Nota per i tipi preset
		pPresetNote = new FlxText(PX, 150, 590, '', 11);
		pPresetNote.setFormat(Paths.font('vcr.ttf'), 11, 0xFF909090, LEFT);
		pPresetNote.wordWrap = true;
		detailAll.push(pPresetNote);
		tab.add(pPresetNote);

		// ---------------- Default ----------------
		pDefLbl = makeLabel('Default value:', PX, 235);
		detailAll.push(pDefLbl);
		tab.add(pDefLbl);

		pDefText = new PsychUIInputText(PX, 253, 300, '', 10);
		pDefText.onChange = function(_, cur:String)
		{
			var p = curParam();
			if (p == null)
				return;
			p.defaultValue = cur;
			paramChanged();
		};
		detailAll.push(pDefText);
		tab.add(pDefText);

		pDefNum = new PsychUINumericStepper(PX, 253, 1, 0, -99999, 99999, 0, 120);
		pDefNum.onValueChange = function()
		{
			var p = curParam();
			if (p == null)
				return;
			p.defaultValue = (p.type == 'int') ? Std.string(Math.round(pDefNum.value)) : Std.string(pDefNum.value);
			paramChanged();
		};
		detailAll.push(pDefNum);
		tab.add(pDefNum);

		pDefBool = new PsychUICheckBox(PX, 253, 'Checked by default', 200);
		pDefBool.onClick = function()
		{
			var p = curParam();
			if (p == null)
				return;
			p.defaultValue = pDefBool.checked ? 'true' : 'false';
			paramChanged();
		};
		detailAll.push(pDefBool);
		tab.add(pDefBool);

		pDefColor = new PsychUIInputText(PX, 253, 110, 'FFFFFF', 10);
		pDefColor.onChange = function(_, cur:String)
		{
			var p = curParam();
			if (p == null)
				return;
			p.defaultValue = cur;
			updateSwatch(cur);
			paramChanged();
		};
		detailAll.push(pDefColor);
		tab.add(pDefColor);

		pDefSwatch = new FlxSprite(PX + 125, 253).makeGraphic(20, 20, FlxColor.WHITE);
		detailAll.push(pDefSwatch);
		tab.add(pDefSwatch);

		// Info (sempre visibile con un parametro selezionato)
		pInfoText = new FlxText(PX, 420, 590, '', 11);
		pInfoText.setFormat(Paths.font('vcr.ttf'), 11, 0xFFE0E0E0, LEFT);
		pInfoText.wordWrap = true;
		tab.add(pInfoText);

		// Il dropdown per ultimo: la sua lista aperta si disegna sopra tutto il resto,
		// e sotto di lui (fino a ~170 px) non c'e' nessun widget cliccabile.
		pDefDD = new PsychUIDropDownMenu(PX, 253, ['-'], function(_:Int, label:String)
		{
			var p = curParam();
			if (p == null || label.startsWith('('))
				return;
			p.defaultValue = label;
			paramChanged();
		}, 300, 8);
		detailAll.push(pDefDD);
		tab.add(pDefDD);
	}

	// ---------------- helper di selezione ----------------

	function curParam():ParamDef
		return (selParam >= 0 && selParam < project.params.length) ? project.params[selParam] : null;

	function show(s:FlxSprite, v:Bool):Void
	{
		if (s != null)
			s.exists = v;
	}

	function showAll(list:Array<FlxSprite>, v:Bool):Void
	{
		for (s in list)
			show(s, v);
	}

	function styleBtn(b:PsychUIButton, selected:Bool):Void
	{
		b.normalStyle.bgColor = selected ? 0xFF2F6FDF : 0xFFAAAAAA;
		b.normalStyle.textColor = selected ? FlxColor.WHITE : FlxColor.BLACK;
		b.bg.color = b.normalStyle.bgColor;
		b.text.color = b.normalStyle.textColor;
		b.forceCheckNext = true;
	}

	function selectParam(i:Int):Void
	{
		if (i < 0 || i >= project.params.length)
			return;
		// prima si toglie il focus: lo unfocus di uno stepper puo' richiamare il suo callback
		// e deve scrivere sul parametro VECCHIO.
		PsychUIInputText.focusOn = null;
		selParam = i;
		refreshParamRows();
		loadParamIntoPanel();
	}

	function rowLabel(q:ParamDef, slot:Int):String
	{
		var badge:String = (slot > 0) ? '[V' + slot + ']' : '[--]';
		var s:String = badge + ' ' + q.name + ' (' + q.type + ')';
		if (s.length > 36)
			s = s.substr(0, 35) + '~';
		return s;
	}

	function refreshParamRows():Void
	{
		if (paramRows.length == 0)
			return;

		var expo:Array<Int> = EventCodegen.exposure(project);
		for (i in 0...paramRows.length)
		{
			var row = paramRows[i];
			if (i < project.params.length)
			{
				row.exists = true;
				row.label = rowLabel(project.params[i], expo[i]);
				styleBtn(row, i == selParam);
			}
			else
				row.exists = false;
		}

		if (paramCountText != null)
			paramCountText.text = '[V1] / [V2] = edited in the chart\n[--] = fixed constant in the Lua file\n'
				+ project.params.length + ' / ' + MAX_PARAMS + ' parameters';
	}

	/** Dopo ogni modifica di un parametro. */
	function paramChanged():Void
	{
		unsavedProgress = true;
		refreshParamRows();
		refreshSummary();
		updateParamInfo();
		refreshCodePreview();
		setStatus('Modified.');
	}

	function updateParamInfo():Void
	{
		if (pInfoText == null)
			return;

		var p = curParam();
		if (p == null)
		{
			pInfoText.text = '';
			return;
		}

		var slot:Int = EventCodegen.exposure(project)[selParam];
		var where:String = (slot > 0) ? 'Chart: the charter edits it as value' + slot : 'Fixed: constant written in the Lua file';
		pInfoText.text = where + '\nLua: ' + EventCodegen.bindingLine(project, selParam);
		pVarText.text = 'Lua variable: ' + EventCodegen.ident(p.name);
	}

	/** Mostra/nasconde i widget giusti e li riempie con i dati del parametro selezionato. */
	function loadParamIntoPanel():Void
	{
		var p = curParam();
		var has:Bool = (p != null);

		showAll(detailAll, has);
		show(pHintText, !has);
		show(pInfoText, has);
		if (!has)
		{
			updateParamInfo();
			return;
		}

		pName.text = p.name;
		for (i in 0...pTypeBtns.length)
			styleBtn(pTypeBtns[i], ParamTypes.ALL[i] == p.type);

		var t:String = p.type;
		var isNum:Bool = ParamTypes.isNumeric(t);
		var isPreset:Bool = ParamTypes.isPreset(t);
		var ranged:Bool = (t == 'slider') || ((t == 'int' || t == 'float') && p.useRange);

		show(pRangeCheck, t == 'int' || t == 'float');
		pRangeCheck.checked = p.useRange;

		show(pMinLbl, ranged);
		show(pMaxLbl, ranged);
		show(pMin, ranged);
		show(pMax, ranged);
		show(pStepLbl, t == 'slider');
		show(pStep, t == 'slider');
		if (ranged)
		{
			pMin.value = p.min;
			pMax.value = p.max;
		}
		if (t == 'slider')
			pStep.value = p.step;

		show(pOptionsLbl, t == 'dropdown');
		show(pOptions, t == 'dropdown');
		if (t == 'dropdown')
			pOptions.text = p.options.join(', ');

		show(pPresetNote, isPreset);
		if (isPreset)
			pPresetNote.text = 'The choices are read from the game / active mod folders (' + presetFolderName(t) + ').';

		// widget del default: ne resta visibile uno solo
		show(pDefText, t == 'text');
		show(pDefNum, isNum);
		show(pDefBool, t == 'bool');
		show(pDefColor, t == 'color');
		show(pDefSwatch, t == 'color');
		show(pDefDD, t == 'dropdown' || isPreset);

		if (t == 'text')
			pDefText.text = p.defaultValue;
		if (isNum)
			configDefStepper(p);
		if (t == 'bool')
			pDefBool.checked = (p.defaultValue == 'true');
		if (t == 'color')
		{
			pDefColor.text = p.defaultValue;
			updateSwatch(p.defaultValue);
		}
		if (t == 'dropdown' || isPreset)
			refreshDefaultDropdown(p);

		updateParamInfo();
	}

	function presetFolderName(t:String):String
	{
		switch (t)
		{
			case 'character':
				return 'boyfriend / dad / gf + characters/';
			case 'sound':
				return 'sounds/';
			case 'image':
				return 'images/';
			case 'stage':
				return 'stages/';
			default:
				return '';
		}
	}

	// ---------------- widget del default ----------------

	function decimalsFor(v:Float):Int
	{
		var s:String = Std.string(v);
		var i:Int = s.indexOf('.');
		if (i < 0)
			return 0;
		return Std.int(Math.min(4, s.length - i - 1));
	}

	/** Imposta limiti, passo e valore dello stepper del default secondo tipo e range del parametro. */
	function configDefStepper(p:ParamDef):Void
	{
		var ranged:Bool = (p.type == 'slider') || p.useRange;
		var lo:Float = ranged ? p.min : -99999;
		var hi:Float = ranged ? p.max : 99999;
		if (hi < lo)
			hi = lo;

		// prima si allarga max: impostare min > max sposterebbe l'altro limite
		pDefNum.max = 99999;
		pDefNum.min = lo;
		pDefNum.max = hi;

		if (p.type == 'int')
		{
			pDefNum.decimals = 0;
			pDefNum.step = 1;
		}
		else if (p.type == 'slider')
		{
			pDefNum.decimals = decimalsFor(p.step);
			pDefNum.step = p.step;
		}
		else
		{
			pDefNum.decimals = 3;
			pDefNum.step = 0.1;
		}

		var v:Float = Std.parseFloat(p.defaultValue);
		pDefNum.value = Math.isNaN(v) ? 0 : v;

		// il valore puo' essere stato corretto dai limiti: si riallinea il parametro
		p.defaultValue = (p.type == 'int') ? Std.string(Math.round(pDefNum.value)) : Std.string(pDefNum.value);
	}

	function parseOptions(s:String):Array<String>
	{
		var out:Array<String> = [];
		for (part in s.split(','))
		{
			var t:String = StringTools.trim(part);
			if (t.length > 0 && !out.contains(t))
				out.push(t);
		}
		return out;
	}

	/** Riempie il dropdown del default (opzioni del parametro, oppure preset enumerati dalle cartelle). */
	function refreshDefaultDropdown(p:ParamDef):Void
	{
		var items:Array<String> = (p.type == 'dropdown') ? p.options.copy() : EventPresets.list(p.type);
		var placeholder:Bool = false;

		if (items.length == 0)
		{
			items = ['(none found)'];
			placeholder = true;
		}
		else if (items.indexOf(p.defaultValue) < 0)
		{
			if (p.type != 'dropdown' && p.defaultValue != null && p.defaultValue != '')
				items.insert(0, p.defaultValue); // valore personalizzato che non e' (piu') nella cartella
			else
				p.defaultValue = items[0];
		}

		// la lista non e' mai vuota e la selezione e' sempre valida (il dropdown non regge null)
		pDefDD.list = items;
		pDefDD.selectedLabel = placeholder ? items[0] : p.defaultValue;
	}

	function updateSwatch(hex:String):Void
	{
		var h:String = (hex == null) ? '' : StringTools.trim(hex);
		if (h.charAt(0) == '#')
			h = h.substr(1);
		var c:Null<FlxColor> = FlxColor.fromString('#' + h);
		pDefSwatch.color = (c != null) ? FlxColor.fromRGB(c.red, c.green, c.blue) : FlxColor.WHITE;
	}

	// ---------------- azioni sui parametri ----------------

	function addParam():Void
	{
		if (project.params.length >= MAX_PARAMS)
		{
			setStatus('Maximum ' + MAX_PARAMS + ' parameters.', true);
			return;
		}
		PsychUIInputText.focusOn = null;
		project.params.push(new ParamDef('param' + (project.params.length + 1), 'text'));
		selParam = project.params.length - 1;
		loadParamIntoPanel();
		paramChanged();
	}

	function deleteParam():Void
	{
		var p = curParam();
		if (p == null)
			return;
		PsychUIInputText.focusOn = null;
		project.params.remove(p);
		selParam = (project.params.length == 0) ? -1 : Std.int(Math.min(selParam, project.params.length - 1));
		loadParamIntoPanel();
		paramChanged();
	}

	function moveParam(dir:Int):Void
	{
		var p = curParam();
		var j:Int = selParam + dir;
		if (p == null || j < 0 || j >= project.params.length)
			return;
		PsychUIInputText.focusOn = null;
		project.params[selParam] = project.params[j];
		project.params[j] = p;
		selParam = j;
		paramChanged();
	}

	function toggleFixed():Void
	{
		var p = curParam();
		if (p == null)
			return;
		p.fixed = !p.fixed;
		paramChanged();
	}

	function defaultFor(t:String, p:ParamDef):String
	{
		var old:Float = Std.parseFloat(p.defaultValue);
		switch (t)
		{
			case 'int':
				return Std.string(Math.round(Math.isNaN(old) ? 0 : old));
			case 'float':
				return Math.isNaN(old) ? '0' : Std.string(old);
			case 'slider':
				return Math.isNaN(old) ? '0.5' : Std.string(old);
			case 'bool':
				return 'false';
			case 'color':
				return 'FFFFFF';
			case 'character':
				return 'boyfriend';
			case 'dropdown':
				return (p.options.length > 0) ? p.options[0] : '';
			default:
				return ''; // text; sound/image/stage: refreshDefaultDropdown sceglie il primo
		}
	}

	function setParamType(t:String):Void
	{
		var p = curParam();
		if (p == null || p.type == t)
			return;

		PsychUIInputText.focusOn = null;
		p.type = t;

		if (t == 'slider')
		{
			p.useRange = true;
			if (p.max <= p.min)
			{
				p.min = 0;
				p.max = 1;
			}
			if (p.step <= 0)
				p.step = 0.05;
		}
		if (t == 'dropdown' && p.options.length == 0)
			p.options = ['option1', 'option2'];

		p.defaultValue = defaultFor(t, p);
		loadParamIntoPanel();
		paramChanged();
	}

	// ================================================================
	// TAB ACTIONS  (lista a sinistra, campi del blocco a destra)
	// ================================================================
	function setupActionsTab():Void
	{
		var tab = mainBox.getTab('Actions').menu;

		// ---------------- colonna sinistra: lista blocchi ----------------
		tab.add(makeLabel('Blocks in event:', 15, 20));
		for (i in 0...MAX_BLOCKS)
		{
			var idx:Int = i;
			var row = new PsychUIButton(15, 38 + i * 20, '', function() selectBlock(idx), 240, 18);
			actionRows.push(row);
			tab.add(row);
		}

		var by:Int = 38 + MAX_BLOCKS * 20 + 6;
		actionToolbar.push(new PsychUIButton(15, by, '+ Add block...', openPalette, 240));
		actionToolbar.push(new PsychUIButton(15, by + 26, 'Delete', deleteBlock, 70));
		actionToolbar.push(new PsychUIButton(90, by + 26, 'Up', function() moveBlock(-1), 45));
		actionToolbar.push(new PsychUIButton(140, by + 26, 'Down', function() moveBlock(1), 50));
		actionToolbar.push(new PsychUIButton(195, by + 26, 'Dup', duplicateBlock, 60));
		for (b in actionToolbar)
			tab.add(b);

		actionCountText = new FlxText(15, by + 54, 245, '', 10);
		actionCountText.setFormat(Paths.font('vcr.ttf'), 10, 0xFF909090, LEFT);
		actionCountText.wordWrap = true;
		tab.add(actionCountText);

		// ---------------- pannello di dettaglio ----------------
		aHintText = new FlxText(PX, 20, 590,
			'Actions are the Lua calls that run when the event fires.\n\n'
			+ 'Blocks run top to bottom. A Wait block delays everything after it '
			+ '(via runTimer + onTimerCompleted).\n\n'
			+ 'Press "+ Add block..." to open the palette.',
			12);
		aHintText.setFormat(Paths.font('vcr.ttf'), 12, 0xFF909090, LEFT);
		aHintText.wordWrap = true;
		tab.add(aHintText);

		aTitleText = new FlxText(PX, 20, 590, '', 14);
		aTitleText.setFormat(Paths.font('vcr.ttf'), 14, FlxColor.WHITE, LEFT);
		aDetailAll.push(aTitleText);
		tab.add(aTitleText);

		aDescText = new FlxText(PX, 42, 590, '', 11);
		aDescText.setFormat(Paths.font('vcr.ttf'), 11, 0xFF909090, LEFT);
		aDescText.wordWrap = true;
		aDetailAll.push(aDescText);
		tab.add(aDescText);

		// Pool di campi (creati una volta sola)
		for (i in 0...MAX_BLOCK_FIELDS)
		{
			var idx:Int = i;
			var fy:Float = 78 + i * 36;

			var lbl = makeLabel('', PX, fy);
			aFieldLbls.push(lbl);
			aDetailAll.push(lbl);
			tab.add(lbl);

			var inp = new PsychUIInputText(PX + 130, fy, 320, '', 10);
			inp.onChange = function(_, cur:String) onBlockFieldChangedByIndex(idx, cur);
			aFieldInputs.push(inp);
			aDetailAll.push(inp);
			tab.add(inp);

			var sw = new FlxSprite(PX + 455, fy).makeGraphic(20, 20, FlxColor.WHITE);
			aFieldSwatches.push(sw);
			aDetailAll.push(sw);
			tab.add(sw);

			var bind = new PsychUIButton(PX + 480, fy, '$', function() openParamPicker(idx), 28, 20);
			bind.normalStyle.bgColor = 0xFF3A6A9A;
			bind.normalStyle.textColor = FlxColor.WHITE;
			aFieldBindBtns.push(bind);
			aDetailAll.push(bind);
			tab.add(bind);

			aFieldKeys.push(null);
		}

		// Dropdown per ultimi: lista aperta sopra tutto. Pool separato dal text input.
		for (i in 0...MAX_BLOCK_FIELDS)
		{
			var idx:Int = i;
			var fy:Float = 78 + i * 36;
			var dd = new PsychUIDropDownMenu(PX + 130, fy, ['-'], function(_:Int, label:String)
			{
				if (label == null || label.startsWith('('))
					return;
				onBlockFieldChangedByIndex(idx, label);
			}, 320, 8);
			aFieldDDs.push(dd);
			aDetailAll.push(dd);
			tab.add(dd);
		}

		aPreviewText = new FlxText(PX, 380, 590, '', 11);
		aPreviewText.setFormat(Paths.font('vcr.ttf'), 11, 0xFF9FDFFF, LEFT);
		aPreviewText.wordWrap = true;
		aDetailAll.push(aPreviewText);
		tab.add(aPreviewText);

		setupPalettePopup(tab);
		setupParamPickerPopup(tab);
	}

	function curBlock():BlockInstance
		return (selBlock >= 0 && selBlock < project.blocks.length) ? project.blocks[selBlock] : null;

	function curBlockDef():BlockDef
	{
		var b = curBlock();
		return (b != null) ? EventPalette.get(b.id) : null;
	}

	/** true mentre un popup Actions e' aperto (i click PsychUI ignorano lo z-order). */
	function actionsBusy():Bool
		return paletteOpen || paramPickerOpen;

	/**
	 * Nasconde lista/dettaglio/toolbar dietro il popup.
	 * exists=false (non solo visible) cosi' i click non passano.
	 */
	function setActionsChromeVisible(v:Bool):Void
	{
		for (b in actionToolbar)
			show(b, v);

		if (actionCountText != null)
			show(actionCountText, v);

		if (!v)
		{
			for (row in actionRows)
				show(row, false);
			showAll(aDetailAll, false);
			show(aHintText, false);
		}
		else
		{
			refreshActionRows();
			loadBlockIntoDetail();
		}
	}

	function blockRowLabel(inst:BlockInstance, index:Int):String
	{
		var def:BlockDef = EventPalette.get(inst.id);
		var name:String = (def != null) ? def.name : ('?' + inst.id);
		var s:String = '[' + (index + 1) + '] ' + name;
		if (s.length > 34)
			s = s.substr(0, 33) + '~';
		return s;
	}

	function refreshActionRows():Void
	{
		if (actionRows.length == 0)
			return;

		for (i in 0...actionRows.length)
		{
			var row = actionRows[i];
			if (i < project.blocks.length)
			{
				row.exists = true;
				row.label = blockRowLabel(project.blocks[i], i);
				styleBtn(row, i == selBlock);
			}
			else
				row.exists = false;
		}

		if (actionCountText != null)
			actionCountText.text = project.blocks.length + ' / ' + MAX_BLOCKS + ' blocks\n'
				+ 'Wait delays everything after it.';
	}

	function selectBlock(i:Int):Void
	{
		if (actionsBusy() || i < 0 || i >= project.blocks.length)
			return;
		PsychUIInputText.focusOn = null;
		selBlock = i;
		refreshActionRows();
		loadBlockIntoDetail();
	}

	function actionChanged():Void
	{
		unsavedProgress = true;
		refreshActionRows();
		refreshSummary();
		updateBlockPreview();
		refreshCodePreview();
		setStatus('Modified.');
	}

	/** Mostra/nasconde i widget del dettaglio e li riempie col blocco selezionato. */
	function loadBlockIntoDetail():Void
	{
		var inst = curBlock();
		var def = curBlockDef();
		var has:Bool = (inst != null && def != null);

		showAll(aDetailAll, false);
		show(aHintText, !has);
		if (!has)
		{
			if (aPreviewText != null)
				aPreviewText.text = '';
			return;
		}

		show(aTitleText, true);
		show(aDescText, true);
		show(aPreviewText, true);
		aTitleText.text = 'Detail of "' + def.name + '"';
		aDescText.text = (def.desc != null && def.desc.length > 0) ? def.desc : (def.category + ' block');

		// Campi visibili (skip tag)
		var slot:Int = 0;
		for (f in def.fields)
		{
			if (f.type == 'tag')
				continue;
			if (slot >= MAX_BLOCK_FIELDS)
				break;

			aFieldKeys[slot] = f.key;
			configureBlockFieldWidget(slot, f, inst);
			slot++;
		}
		for (i in slot...MAX_BLOCK_FIELDS)
		{
			aFieldKeys[i] = null;
			show(aFieldLbls[i], false);
			show(aFieldInputs[i], false);
			show(aFieldDDs[i], false);
			show(aFieldSwatches[i], false);
			show(aFieldBindBtns[i], false);
		}

		updateBlockPreview();
	}

	function usesDropdown(fieldType:String):Bool
	{
		return fieldType == 'ease'
			|| fieldType == 'dropdown'
			|| fieldType == 'object'
			|| fieldType == 'characterfile'
			|| fieldType == 'sound'
			|| fieldType == 'image'
			|| fieldType == 'stage';
	}

	function optionsForField(f:BlockFieldDef):Array<String>
	{
		switch (f.type)
		{
			case 'ease':
				return EASE_OPTIONS.copy();
			case 'object':
				return OBJECT_OPTIONS.copy();
			case 'dropdown':
				return (f.options != null) ? f.options.copy() : [];
			case 'characterfile':
				return EventPresets.list('characterfile');
			case 'sound':
				return EventPresets.list('sound');
			case 'image':
				return EventPresets.list('image');
			case 'stage':
				return EventPresets.list('stage');
			default:
				return [];
		}
	}

	function configureBlockFieldWidget(slot:Int, f:BlockFieldDef, inst:BlockInstance):Void
	{
		var raw:String = inst.get(f.key);
		if (raw == null)
			raw = (f.def != null) ? f.def : '';

		aFieldLbls[slot].text = f.label + ':';
		show(aFieldLbls[slot], true);
		show(aFieldBindBtns[slot], true);

		var isDD:Bool = usesDropdown(f.type);
		var isColor:Bool = (f.type == 'color');

		show(aFieldInputs[slot], !isDD);
		show(aFieldDDs[slot], isDD);
		show(aFieldSwatches[slot], isColor);

		if (isDD)
		{
			var items:Array<String> = optionsForField(f);
			var placeholder:Bool = false;
			if (items.length == 0)
			{
				items = ['(none found)'];
				placeholder = true;
			}
			else if (items.indexOf(raw) < 0 && raw != null && raw != '')
				items.insert(0, raw);

			aFieldDDs[slot].list = items;
			aFieldDDs[slot].selectedLabel = placeholder ? items[0] : ((items.indexOf(raw) >= 0) ? raw : items[0]);
			if (!placeholder && (inst.get(f.key) == null || inst.get(f.key) == ''))
				inst.set(f.key, aFieldDDs[slot].selectedLabel);
		}
		else
		{
			aFieldInputs[slot].text = raw;
			if (isColor)
				updateBlockSwatch(slot, raw);
		}
	}

	function updateBlockSwatch(slot:Int, hex:String):Void
	{
		var h:String = (hex == null) ? '' : StringTools.trim(hex);
		if (h.charAt(0) == '#')
			h = h.substr(1);
		if (h.charAt(0) == '$')
		{
			aFieldSwatches[slot].color = 0xFF808080;
			return;
		}
		var c:Null<FlxColor> = FlxColor.fromString('#' + h);
		aFieldSwatches[slot].color = (c != null) ? FlxColor.fromRGB(c.red, c.green, c.blue) : FlxColor.WHITE;
	}

	function onBlockFieldChangedByIndex(slot:Int, value:String):Void
	{
		if (actionsBusy())
			return;
		var inst = curBlock();
		var key:String = (slot >= 0 && slot < aFieldKeys.length) ? aFieldKeys[slot] : null;
		if (inst == null || key == null)
			return;

		inst.set(key, value);
		if (aFieldSwatches[slot] != null && aFieldSwatches[slot].exists)
			updateBlockSwatch(slot, value);
		actionChanged();
	}

	function updateBlockPreview():Void
	{
		if (aPreviewText == null)
			return;
		if (curBlock() == null)
		{
			aPreviewText.text = '';
			return;
		}
		var lua:String = EventCodegen.previewBlock(project, selBlock);
		aPreviewText.text = 'Preview:\n' + lua;
	}

	// ---------------- azioni sui blocchi ----------------

	function addBlockFromPalette(def:BlockDef):Void
	{
		if (def == null)
			return;
		if (project.blocks.length >= MAX_BLOCKS)
		{
			setStatus('Maximum ' + MAX_BLOCKS + ' blocks.', true);
			return;
		}

		PsychUIInputText.focusOn = null;
		var inst = new BlockInstance(def.id);
		for (f in def.fields)
		{
			if (f.type == 'tag')
				continue;
			inst.set(f.key, (f.def != null) ? f.def : '');
		}
		project.blocks.push(inst);
		selBlock = project.blocks.length - 1;
		closePalette();
		loadBlockIntoDetail();
		actionChanged();
	}

	function deleteBlock():Void
	{
		if (actionsBusy())
			return;
		var b = curBlock();
		if (b == null)
			return;
		PsychUIInputText.focusOn = null;
		project.blocks.remove(b);
		selBlock = (project.blocks.length == 0) ? -1 : Std.int(Math.min(selBlock, project.blocks.length - 1));
		loadBlockIntoDetail();
		actionChanged();
	}

	function moveBlock(dir:Int):Void
	{
		if (actionsBusy())
			return;
		var b = curBlock();
		var j:Int = selBlock + dir;
		if (b == null || j < 0 || j >= project.blocks.length)
			return;
		PsychUIInputText.focusOn = null;
		project.blocks[selBlock] = project.blocks[j];
		project.blocks[j] = b;
		selBlock = j;
		loadBlockIntoDetail();
		actionChanged();
	}

	function duplicateBlock():Void
	{
		if (actionsBusy())
			return;
		var b = curBlock();
		if (b == null)
			return;
		if (project.blocks.length >= MAX_BLOCKS)
		{
			setStatus('Maximum ' + MAX_BLOCKS + ' blocks.', true);
			return;
		}

		PsychUIInputText.focusOn = null;
		var copy = new BlockInstance(b.id);
		for (k in Reflect.fields(b.fields))
			Reflect.setField(copy.fields, k, Reflect.field(b.fields, k));
		project.blocks.insert(selBlock + 1, copy);
		selBlock = selBlock + 1;
		loadBlockIntoDetail();
		actionChanged();
	}

	// ---------------- palette popup ----------------

	function setupPalettePopup(tab:FlxSpriteGroup):Void
	{
		paletteOverlay = new FlxSprite(0, 0).makeGraphic(1, 1, 0xCC000000);
		paletteOverlay.setGraphicSize(BOX_W, BOX_H - 30);
		paletteOverlay.updateHitbox();
		paletteWidgets.push(paletteOverlay);
		tab.add(paletteOverlay);

		palettePanel = new FlxSprite(40, 20).makeGraphic(1, 1, 0xFF1E1E2E);
		palettePanel.setGraphicSize(BOX_W - 80, BOX_H - 70);
		palettePanel.updateHitbox();
		paletteWidgets.push(palettePanel);
		tab.add(palettePanel);

		paletteTitle = new FlxText(55, 30, BOX_W - 110, 'Add block — pick from the palette', 14);
		paletteTitle.setFormat(Paths.font('vcr.ttf'), 14, FlxColor.WHITE, LEFT);
		paletteWidgets.push(paletteTitle);
		tab.add(paletteTitle);

		paletteSearch = new PsychUIInputText(55, 55, 400, '', 10);
		paletteSearch.onChange = function(_, cur:String)
		{
			paletteScroll = 0;
			refreshPaletteRows(cur);
		};
		paletteWidgets.push(paletteSearch);
		tab.add(paletteSearch);

		paletteHint = new FlxText(470, 55, 350, 'Type to filter  |  ESC to close  |  mouse wheel to scroll', 11);
		paletteHint.setFormat(Paths.font('vcr.ttf'), 11, 0xFF909090, LEFT);
		paletteWidgets.push(paletteHint);
		tab.add(paletteHint);

		for (i in 0...PALETTE_VISIBLE)
		{
			var idx:Int = i;
			var row = new PsychUIButton(55, 90 + i * 28, '', function()
			{
				var abs:Int = paletteScroll + idx;
				if (abs >= 0 && abs < paletteFiltered.length)
					addBlockFromPalette(paletteFiltered[abs]);
			}, BOX_W - 120, 24);
			paletteRows.push(row);
			paletteWidgets.push(row);
			tab.add(row);
		}

		setPaletteVisible(false);
	}

	function setPaletteVisible(v:Bool):Void
	{
		paletteOpen = v;
		for (w in paletteWidgets)
			show(w, v);
	}

	function openPalette():Void
	{
		if (paletteOpen)
			return;
		if (project.blocks.length >= MAX_BLOCKS)
		{
			setStatus('Maximum ' + MAX_BLOCKS + ' blocks.', true);
			return;
		}
		closeParamPicker();
		PsychUIInputText.focusOn = null;
		paletteSearch.text = '';
		paletteScroll = 0;
		setActionsChromeVisible(false);
		refreshPaletteRows('');
		setPaletteVisible(true);
		PsychUIInputText.focusOn = paletteSearch;
	}

	function closePalette():Void
	{
		if (!paletteOpen)
			return;
		PsychUIInputText.focusOn = null;
		setPaletteVisible(false);
		if (!paramPickerOpen)
			setActionsChromeVisible(true);
	}

	function refreshPaletteRows(?filter:String):Void
	{
		var q:String = (filter != null) ? filter : paletteSearch.text;
		q = (q == null) ? '' : q.trim().toLowerCase();

		paletteFiltered = [];
		for (b in EventPalette.blocks)
		{
			if (q.length == 0
				|| b.name.toLowerCase().indexOf(q) >= 0
				|| b.id.toLowerCase().indexOf(q) >= 0
				|| (b.category != null && b.category.toLowerCase().indexOf(q) >= 0)
				|| (b.desc != null && b.desc.toLowerCase().indexOf(q) >= 0))
				paletteFiltered.push(b);
		}

		var maxScroll:Int = Std.int(Math.max(0, paletteFiltered.length - PALETTE_VISIBLE));
		if (paletteScroll > maxScroll)
			paletteScroll = maxScroll;
		if (paletteScroll < 0)
			paletteScroll = 0;

		for (i in 0...paletteRows.length)
		{
			var abs:Int = paletteScroll + i;
			var row = paletteRows[i];
			if (abs < paletteFiltered.length)
			{
				var b:BlockDef = paletteFiltered[abs];
				var desc:String = (b.desc != null && b.desc.length > 0) ? (' — ' + b.desc) : '';
				var label:String = '[' + b.category + '] ' + b.name + desc;
				if (label.length > 70)
					label = label.substr(0, 69) + '~';
				row.exists = paletteOpen;
				row.label = label;
			}
			else
				row.exists = false;
		}

		if (paletteHint != null && paletteOpen)
		{
			paletteHint.text = paletteFiltered.length + ' blocks'
				+ ((paletteFiltered.length > PALETTE_VISIBLE) ? ('  (scroll ' + (paletteScroll + 1) + '-'
					+ Std.int(Math.min(paletteScroll + PALETTE_VISIBLE, paletteFiltered.length)) + ')') : '')
				+ '  |  ESC to close';
		}
	}

	function updatePaletteScroll():Void
	{
		if (!paletteOpen)
			return;
		var wheel:Float = FlxG.mouse.wheel;
		if (wheel == 0)
			return;
		paletteScroll -= Std.int(wheel);
		refreshPaletteRows();
	}

	// ---------------- param picker popup ----------------

	function setupParamPickerPopup(tab:FlxSpriteGroup):Void
	{
		paramPickerOverlay = new FlxSprite(0, 0).makeGraphic(1, 1, 0xCC000000);
		paramPickerOverlay.setGraphicSize(BOX_W, BOX_H - 30);
		paramPickerOverlay.updateHitbox();
		paramPickerWidgets.push(paramPickerOverlay);
		tab.add(paramPickerOverlay);

		paramPickerPanel = new FlxSprite(200, 60).makeGraphic(1, 1, 0xFF1E1E2E);
		paramPickerPanel.setGraphicSize(480, 360);
		paramPickerPanel.updateHitbox();
		paramPickerWidgets.push(paramPickerPanel);
		tab.add(paramPickerPanel);

		paramPickerTitle = new FlxText(215, 70, 450, 'Bind field to a parameter', 14);
		paramPickerTitle.setFormat(Paths.font('vcr.ttf'), 14, FlxColor.WHITE, LEFT);
		paramPickerWidgets.push(paramPickerTitle);
		tab.add(paramPickerTitle);

		for (i in 0...PARAM_PICKER_VISIBLE)
		{
			var idx:Int = i;
			var row = new PsychUIButton(215, 105 + i * 28, '', function() selectParamForField(idx), 450, 24);
			paramPickerRows.push(row);
			paramPickerWidgets.push(row);
			tab.add(row);
		}

		setParamPickerVisible(false);
	}

	function setParamPickerVisible(v:Bool):Void
	{
		paramPickerOpen = v;
		for (w in paramPickerWidgets)
			show(w, v);
	}

	function openParamPicker(fieldSlot:Int):Void
	{
		if (actionsBusy())
			return;
		if (fieldSlot < 0 || aFieldKeys[fieldSlot] == null || curBlock() == null)
			return;

		if (project.params.length == 0)
		{
			setStatus('No parameters yet — add some in the Parameters tab.', true);
			return;
		}

		PsychUIInputText.focusOn = null;
		paramPickerFieldIdx = fieldSlot;

		paramPickerTitle.text = 'Bind "' + aFieldLbls[fieldSlot].text + '" to a parameter  (ESC to close)';
		for (i in 0...paramPickerRows.length)
		{
			var row = paramPickerRows[i];
			if (i < project.params.length)
			{
				var p:ParamDef = project.params[i];
				row.exists = true;
				row.label = '$' + EventCodegen.ident(p.name) + '  (' + p.name + ' / ' + p.type + ')';
			}
			else
				row.exists = false;
		}
		setActionsChromeVisible(false);
		setParamPickerVisible(true);
	}

	function closeParamPicker():Void
	{
		if (!paramPickerOpen)
			return;
		paramPickerFieldIdx = -1;
		setParamPickerVisible(false);
		if (!paletteOpen)
			setActionsChromeVisible(true);
	}

	function selectParamForField(paramIndex:Int):Void
	{
		if (paramIndex < 0 || paramIndex >= project.params.length)
			return;
		if (paramPickerFieldIdx < 0)
			return;

		var p:ParamDef = project.params[paramIndex];
		var value:String = '$' + EventCodegen.ident(p.name);
		var slot:Int = paramPickerFieldIdx;
		closeParamPicker();

		// Aggiorna widget + progetto
		var key:String = aFieldKeys[slot];
		var inst = curBlock();
		if (inst == null || key == null)
			return;

		inst.set(key, value);
		if (aFieldInputs[slot].exists)
			aFieldInputs[slot].text = value;
		if (aFieldDDs[slot].exists)
		{
			var items:Array<String> = aFieldDDs[slot].list.copy();
			if (items.indexOf(value) < 0)
				items.insert(0, value);
			aFieldDDs[slot].list = items;
			aFieldDDs[slot].selectedLabel = value;
		}
		if (aFieldSwatches[slot].exists)
			updateBlockSwatch(slot, value);
		actionChanged();
	}

	// ================================================================
	// TAB CODE (anteprima live)
	// ================================================================
	function setupCodeTab():Void
	{
		var tab = mainBox.getTab('Code').menu;
		codePreview = new FlxText(10, 20, BOX_W - 20, '', 10);
		// vcr e' monospace e c'e' su ogni piattaforma
		codePreview.setFormat(Paths.font('vcr.ttf'), 10, 0xFFE0E0E0, LEFT);
		codePreview.wordWrap = false;
		tab.add(codePreview);
	}

	function refreshCodePreview():Void
	{
		if (codePreview == null)
			return;

		var res:GenResult = EventCodegen.generate(project, false);
		var lines:Array<String> = [];

		for (e in res.errors.slice(0, 3))
			lines.push('-- ERROR: ' + e);
		for (w in res.warnings.slice(0, 3))
			lines.push('-- WARNING: ' + w);
		if (lines.length > 0)
			lines.push('');

		for (l in res.code.split('\n'))
			lines.push(l);

		if (lines.length > CODE_PREVIEW_LINES)
		{
			var extra:Int = lines.length - CODE_PREVIEW_LINES;
			lines = lines.slice(0, CODE_PREVIEW_LINES);
			lines.push('-- ... (' + extra + ' more lines, see the saved file)');
		}
		codePreview.text = lines.join('\n');
	}

	// ================================================================
	// PERCORSI
	// ================================================================

	/** Cartella di destinazione: mod attiva, altrimenti cartella globale mods/custom_events/. */
	function getEventsFolder():String
	{
		var modDir:String = Mods.currentModDirectory;
		if (modDir != null && modDir.length > 0)
			return 'mods/' + modDir + '/custom_events/';
		return 'mods/custom_events/';
	}

	// ================================================================
	// SUMMARY
	// ================================================================
	function refreshSummary():Void
	{
		if (summaryText == null)
			return;
		summaryText.text = 'Parameters: ' + project.params.length
			+ '  |  Actions: ' + project.blocks.length
			+ '  |  Chart values: ' + project.chartValues;

		if (fileNameText != null)
		{
			var id:String = EventCodegen.eventId(project.name);
			var folder:String = getEventsFolder();
			fileNameText.text = 'File: ' + folder + id + '.lua\n'
				+ '      ' + folder + id + '.txt';
		}
	}

	// ================================================================
	// ESEMPIO / CARICAMENTO PROGETTO
	// ================================================================
	function sampleProject():EventProject
	{
		var p = new EventProject();
		p.name = 'Glitch Effect';
		p.description = 'A glitchy effect on a character';
		p.category = 'Visual';
		p.chartValues = 2;

		var target = new ParamDef('target', 'character');
		target.defaultValue = 'boyfriend';
		p.params.push(target);

		var intensity = new ParamDef('intensity', 'slider');
		intensity.useRange = true;
		intensity.min = 0;
		intensity.max = 1;
		intensity.step = 0.05;
		intensity.defaultValue = '0.5';
		p.params.push(intensity);

		// NB: stringhe tra virgolette doppie, perche' in Haxe '$x' tra apici singoli viene interpolato
		var b1 = new BlockInstance('play_sound');
		b1.set('sound', 'glitch');
		b1.set('volume', '1');
		p.blocks.push(b1);

		var b2 = new BlockInstance('tween_angle');
		b2.set('target', "$target");
		b2.set('value', '360');
		b2.set('duration', "$intensity");
		b2.set('ease', 'quadOut');
		p.blocks.push(b2);

		var b3 = new BlockInstance('tween_alpha');
		b3.set('target', "$target");
		b3.set('value', '0');
		b3.set('duration', '0.1');
		b3.set('ease', 'linear');
		p.blocks.push(b3);

		var b4 = new BlockInstance('tween_alpha');
		b4.set('target', "$target");
		b4.set('value', '1');
		b4.set('duration', '0.2');
		b4.set('ease', 'linear');
		p.blocks.push(b4);

		return p;
	}

	function loadSample():Void
	{
		loadProject(sampleProject());
		setStatus('Example loaded: see the Parameters and Code tabs.');
	}

	/** Sostituisce il progetto corrente e riallinea tutta la UI. */
	function loadProject(p:EventProject):Void
	{
		PsychUIInputText.focusOn = null;
		closePalette();
		closeParamPicker();
		project = p;
		selParam = (project.params.length > 0) ? 0 : -1;
		selBlock = (project.blocks.length > 0) ? 0 : -1;

		nameInput.text = p.name;
		descInput.text = p.description;
		categoryDD.selectedLabel = p.category;
		chartValuesStepper.value = p.chartValues;

		refreshParamRows();
		loadParamIntoPanel();
		refreshActionRows();
		loadBlockIntoDetail();
		refreshSummary();
		refreshCodePreview();
		unsavedProgress = true;
	}

	// ================================================================
	// SALVATAGGIO
	// ================================================================
	function doSave():Void
	{
		var res:GenResult = EventCodegen.generate(project, true);
		if (res.errors.length > 0)
		{
			setStatus('ERROR: ' + res.errors[0], true);
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			return;
		}

		var id:String = EventCodegen.eventId(project.name);
		var folder:String = getEventsFolder();
		var luaPath:String = folder + id + '.lua';

		// Mai sovrascrivere in silenzio un file esistente (potrebbe essere stato modificato a mano)
		if (FileSystem.exists(luaPath) && luaPath != lastSavedPath)
		{
			openSubState(new states.editors.content.Prompt(
				'"' + id + '" already exists in custom_events.\nOverwrite it?',
				function() writeEvent(folder, id, res)
			));
			return;
		}

		writeEvent(folder, id, res);
	}

	function writeEvent(folder:String, id:String, res:GenResult):Void
	{
		try
		{
			if (!FileSystem.exists(folder))
				FileSystem.createDirectory(folder);

			var luaPath:String = folder + id + '.lua';
			var txtPath:String = folder + id + '.txt';

			File.saveContent(luaPath, res.code);
			File.saveContent(txtPath, EventCodegen.generateDescription(project));

			lastSavedPath = luaPath;
			unsavedProgress = false;

			var where:String = (Mods.currentModDirectory == null || Mods.currentModDirectory.length < 1) ? ' (global, no active mod)' : '';
			var warn:String = (res.warnings.length > 0) ? ' - ' + res.warnings.length + ' warning(s), see the Code tab' : '';
			setStatus('Saved ' + luaPath + ' + .txt' + where + warn, false, 0xFF70D070);
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

		// Chiudi i popup se si cambia tab
		if (mainBox != null && mainBox.selectedName != 'Actions')
		{
			if (paletteOpen)
				closePalette();
			if (paramPickerOpen)
				closeParamPicker();
		}

		updatePaletteScroll();

		// ESC: prima chiude i popup Actions, poi esce
		if (FlxG.keys.justPressed.ESCAPE)
		{
			if (paramPickerOpen)
			{
				closeParamPicker();
				return;
			}
			if (paletteOpen)
			{
				closePalette();
				return;
			}
			if (PsychUIInputText.focusOn == null)
			{
				requestExit();
				return;
			}
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
		// I widget usano .onChange / .onClick / .onValueChange: qui non serve nulla.
	}

	// ================================================================
	// UTILITY
	// ================================================================
	function setStatus(msg:String, isError:Bool = false, ?color:FlxColor):Void
	{
		if (statusText == null)
			return;
		statusText.text = msg;
		statusText.color = (color != null) ? color : (isError ? 0xFFFF6060 : FlxColor.WHITE);
	}
}
