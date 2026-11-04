package states.editors;

import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import flash.net.FileFilter;
import haxe.Json;
import cutscenes.DialogueBoxPixel;
import states.editors.content.Prompt;

/**
 * Editor dei dialoghi pixel (Week 6).
 * - L'anteprima è la VERA DialogueBoxPixel (stessa classe del gioco), quindi quello che vedi è quello che ottieni.
 * - I personaggi vengono dai .json nella cartella "characters/" (fuori da images).
 * - Il ritratto di ogni personaggio è images/custom_dialogs/dialogPortraits/portrait_<nome>.png + .xml
 * - Salva un file da mettere in data/<canzone>/dialogue-pixel.json
 *
 * Tasti: A/D riga precedente/successiva, W/S espressione, O elimina riga, P aggiungi riga, SPACE rivedi la riga, ESC esci.
 */
class DialoguePixelEditorState extends MusicBeatState implements PsychUIEventHandler.PsychUIEvent
{
	var dialogueFile:PixelDialogueFile = null;
	var previewBox:DialogueBoxPixel = null;

	var selectedText:FlxText;
	var infoText:FlxText;

	var curSelected:Int = 0;
	var unsavedProgress:Bool = false;
	var transitioning:Bool = false;

	var characters:Array<String> = [];
	var boxes:Array<String> = [];

	var UI_box:PsychUIBox;

	// tab "Riga"
	var characterInput:PsychUIInputText;
	var expressionInput:PsychUIInputText;
	var rightCheckbox:PsychUICheckBox;
	var flipCheckbox:PsychUICheckBox;
	var speedStepper:PsychUINumericStepper;
	var soundInput:PsychUIInputText;
	var lineInput:PsychUIInputText;

	// tab "File"
	var boxInput:PsychUIInputText;
	var handInput:PsychUIInputText;
	var bgColorInput:PsychUIInputText;
	var textColorInput:PsychUIInputText;
	var shadowColorInput:PsychUIInputText;

	override function create()
	{
		persistentUpdate = persistentDraw = true;
		FlxG.camera.bgColor = FlxColor.fromHSL(0, 0, 0.5);

		characters = DialogueBoxPixel.listCharacters();
		boxes = DialogueBoxPixel.listBoxes();

		dialogueFile = {
			dialogue: [newLine()],
			box: boxes[0],
			hand: DialogueBoxPixel.DEFAULT_HAND,
			bgFadeColor: '#B3DFD8',
			textColor: '',
			shadowColor: ''
		};

		rebuildPreview();

		selectedText = new FlxText(10, 10, FlxG.width - 380, '', 8);
		selectedText.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		selectedText.scrollFactor.set();
		add(selectedText);

		infoText = new FlxText(10, 66, FlxG.width - 380, '', 8);
		infoText.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		infoText.scrollFactor.set();
		add(infoText);

		addEditorBox();
		FlxG.mouse.visible = true;

		changeLine(0);
		super.create();
	}

	// ------------------------------------------------------------------
	// Anteprima
	// ------------------------------------------------------------------
	function rebuildPreview():Void
	{
		if (previewBox != null)
		{
			remove(previewBox, true);
			previewBox.destroy();
		}
		previewBox = new DialogueBoxPixel(dialogueFile, true);
		insert(0, previewBox); // sempre dietro all'interfaccia
		previewBox.setPreviewLine(curSelected, true);
	}

	function refreshLine(instant:Bool, markUnsaved:Bool):Void
	{
		if (markUnsaved)
			unsavedProgress = true;
		if (previewBox != null)
			previewBox.setPreviewLine(curSelected, instant);
		updateInfo();
	}

	function updateInfo():Void
	{
		var line:PixelDialogueLine = dialogueFile.dialogue[curSelected];

		selectedText.text = 'Line ('
			+ (curSelected + 1)
			+ ' / '
			+ dialogueFile.dialogue.length
			+ ') - A/D = line, W/S = expression, SPACE = replay, O/P = delete/add';

		if (line.portrait == null || line.portrait.length < 1)
		{
			infoText.text = 'No portrait (character field is empty)';
			return;
		}

		var frames = DialogueBoxPixel.loadPortraitFrames(line.portrait);
		if (frames == null)
		{
			infoText.text = 'Portrait NOT found: images/custom_dialogs/dialogPortraits/portrait_' + line.portrait + '.png + .xml';
			return;
		}
		infoText.text = 'Expressions: ' + DialogueBoxPixel.getExpressions(frames).join(', ');
	}

	// ------------------------------------------------------------------
	// Dati
	// ------------------------------------------------------------------
	function pickDefaultCharacter():String
	{
		for (c in characters)
		{
			if (DialogueBoxPixel.loadPortraitFrames(c) != null)
				return c;
		}
		return (characters.length > 0) ? characters[0] : '';
	}

	function firstExpression(character:String):String
	{
		var list:Array<String> = DialogueBoxPixel.getExpressions(DialogueBoxPixel.loadPortraitFrames(character));
		return (list.length > 0) ? list[0] : '';
	}

	function newLine():PixelDialogueLine
	{
		var c:String = pickDefaultCharacter();
		return {
			portrait: c,
			expression: firstExpression(c),
			side: 'left',
			text: 'coolswag',
			speed: 0.04,
			sound: DialogueBoxPixel.DEFAULT_SOUND,
			flip: false
		};
	}

	function copyLine(src:PixelDialogueLine):PixelDialogueLine
	{
		return {
			portrait: src.portrait,
			expression: src.expression,
			side: src.side,
			text: src.text,
			speed: src.speed,
			sound: src.sound,
			flip: src.flip
		};
	}

	/** Se l'espressione della riga non esiste nel ritratto, passa alla prima disponibile. */
	function fixExpression(line:PixelDialogueLine):Void
	{
		var list:Array<String> = DialogueBoxPixel.getExpressions(DialogueBoxPixel.loadPortraitFrames(line.portrait));
		if (list.length < 1)
			line.expression = '';
		else if (list.indexOf(line.expression) < 0)
			line.expression = list[0];
		expressionInput.text = line.expression;
	}

	function cycleCharacter(dir:Int):Void
	{
		if (characters.length < 1)
			return;
		var line:PixelDialogueLine = dialogueFile.dialogue[curSelected];
		var idx:Int = characters.indexOf(line.portrait);
		if (idx < 0)
			idx = (dir > 0) ? -1 : 0;
		idx = FlxMath.wrap(idx + dir, 0, characters.length - 1);

		line.portrait = characters[idx];
		characterInput.text = line.portrait;
		fixExpression(line);
		refreshLine(true, true);
	}

	function cycleExpression(dir:Int):Void
	{
		var line:PixelDialogueLine = dialogueFile.dialogue[curSelected];
		var list:Array<String> = DialogueBoxPixel.getExpressions(DialogueBoxPixel.loadPortraitFrames(line.portrait));
		if (list.length < 1)
			return;
		var idx:Int = list.indexOf(line.expression);
		if (idx < 0)
			idx = (dir > 0) ? -1 : 0;
		idx = FlxMath.wrap(idx + dir, 0, list.length - 1);

		line.expression = list[idx];
		expressionInput.text = line.expression;
		refreshLine(false, true);
	}

	function cycleBox(dir:Int):Void
	{
		if (boxes.length < 1)
			return;
		var idx:Int = boxes.indexOf(dialogueFile.box);
		if (idx < 0)
			idx = (dir > 0) ? -1 : 0;
		idx = FlxMath.wrap(idx + dir, 0, boxes.length - 1);

		dialogueFile.box = boxes[idx];
		boxInput.text = dialogueFile.box;
		unsavedProgress = true;
		rebuildPreview();
	}

	// ------------------------------------------------------------------
	// Interfaccia
	// ------------------------------------------------------------------
	function addEditorBox():Void
	{
		UI_box = new PsychUIBox(FlxG.width - 350, 10, 340, 290, ['Line', 'File']);
		UI_box.scrollFactor.set();
		addLineTab();
		addFileTab();
		add(UI_box);
	}

	function addLineTab():Void
	{
		var tab = UI_box.getTab('Line').menu;

		characterInput = new PsychUIInputText(10, 22, 120, '', 8);
		var prevChar:PsychUIButton = new PsychUIButton(140, 20, '< Prev.', function() cycleCharacter(-1));
		var nextChar:PsychUIButton = new PsychUIButton(225, 20, 'Next >', function() cycleCharacter(1));

		expressionInput = new PsychUIInputText(10, 68, 120, '', 8);
		var prevExpr:PsychUIButton = new PsychUIButton(140, 66, '< Prev.', function() cycleExpression(-1));
		var nextExpr:PsychUIButton = new PsychUIButton(225, 66, 'Next >', function() cycleExpression(1));

		rightCheckbox = new PsychUICheckBox(10, 98, 'Portrait on the right', 150);
		rightCheckbox.onClick = function()
		{
			var line:PixelDialogueLine = dialogueFile.dialogue[curSelected];
			var newSide:String = rightCheckbox.checked ? 'right' : 'left';
			if (line.side != newSide)
			{
				line.side = newSide;
				refreshLine(true, true);
			}
		};

		flipCheckbox = new PsychUICheckBox(170, 98, 'Flip portrait (mirror)', 150);
		flipCheckbox.onClick = function()
		{
			var line:PixelDialogueLine = dialogueFile.dialogue[curSelected];
			if ((line.flip == true) != flipCheckbox.checked)
			{
				line.flip = flipCheckbox.checked;
				refreshLine(true, true);
			}
		};

		speedStepper = new PsychUINumericStepper(10, 144, 0.005, 0.04, 0.001, 0.5, 3);
		soundInput = new PsychUIInputText(150, 144, 170, DialogueBoxPixel.DEFAULT_SOUND, 8);

		lineInput = new PsychUIInputText(10, 190, 310, '', 8);
		lineInput.onPressEnter = function(e)
		{
			if (e.shiftKey)
			{
				lineInput.text += '\n';
				lineInput.caretIndex++;
			}
			else
				PsychUIInputText.focusOn = null;
		};

		#if !mobile
		var loadButton:PsychUIButton = new PsychUIButton(10, 228, 'Load', function()
		{
			loadDialogue();
		});
		#end
		var saveButton:PsychUIButton = new PsychUIButton(#if mobile 10 #else 130 #end, 228, 'Save', function()
		{
			saveDialogue();
		});

		tab.add(new FlxText(10, 6, 0, 'Character (from characters folder):'));
		tab.add(new FlxText(10, 52, 0, 'Expression (from portrait):'));
		tab.add(new FlxText(10, 128, 0, 'Speed (sec/letter):'));
		tab.add(new FlxText(150, 128, 0, 'Sound (from game):'));
		tab.add(new FlxText(10, 174, 0, 'Text (P = new line):'));
		tab.add(characterInput);
		tab.add(prevChar);
		tab.add(nextChar);
		tab.add(expressionInput);
		tab.add(prevExpr);
		tab.add(nextExpr);
		tab.add(rightCheckbox);
		tab.add(flipCheckbox);
		tab.add(speedStepper);
		tab.add(soundInput);
		tab.add(lineInput);
		#if !mobile tab.add(loadButton); #end
		tab.add(saveButton);
	}

	function addFileTab():Void
	{
		var tab = UI_box.getTab('File').menu;

		boxInput = new PsychUIInputText(10, 22, 120, '', 8);
		var prevBox:PsychUIButton = new PsychUIButton(140, 20, '< Prev.', function() cycleBox(-1));
		var nextBox:PsychUIButton = new PsychUIButton(225, 20, 'Next >', function() cycleBox(1));

		handInput = new PsychUIInputText(10, 68, 150, '', 8);
		bgColorInput = new PsychUIInputText(10, 114, 120, '', 8);
		textColorInput = new PsychUIInputText(10, 160, 120, '', 8);
		shadowColorInput = new PsychUIInputText(150, 160, 120, '', 8);

		tab.add(new FlxText(10, 6, 0, 'Box (dialogBoxes, isPixel):'));
		tab.add(new FlxText(10, 52, 0, 'Hand (dialogHands, no .png):'));
		tab.add(new FlxText(10, 98, 0, 'Background color (#RRGGBB):'));
		tab.add(new FlxText(10, 144, 0, 'Text color (empty = auto):'));
		tab.add(new FlxText(150, 144, 0, 'Shadow color (empty = auto):'));
		tab.add(boxInput);
		tab.add(prevBox);
		tab.add(nextBox);
		tab.add(handInput);
		tab.add(bgColorInput);
		tab.add(textColorInput);
		tab.add(shadowColorInput);
	}

	/** Copia nei campi dell'interfaccia i dati della riga corrente. */
	function changeLine(add:Int = 0):Void
	{
		curSelected = FlxMath.wrap(curSelected + add, 0, dialogueFile.dialogue.length - 1);
		var line:PixelDialogueLine = dialogueFile.dialogue[curSelected];

		characterInput.text = (line.portrait != null) ? line.portrait : '';
		expressionInput.text = (line.expression != null) ? line.expression : '';
		rightCheckbox.checked = (line.side == 'right');
		flipCheckbox.checked = (line.flip == true);
		speedStepper.value = (line.speed != null) ? line.speed : 0.04;
		soundInput.text = (line.sound != null) ? line.sound : DialogueBoxPixel.DEFAULT_SOUND;
		lineInput.text = (line.text != null) ? line.text : '';

		boxInput.text = (dialogueFile.box != null) ? dialogueFile.box : '';
		handInput.text = (dialogueFile.hand != null) ? dialogueFile.hand : '';
		bgColorInput.text = (dialogueFile.bgFadeColor != null) ? dialogueFile.bgFadeColor : '';
		textColorInput.text = (dialogueFile.textColor != null) ? dialogueFile.textColor : '';
		shadowColorInput.text = (dialogueFile.shadowColor != null) ? dialogueFile.shadowColor : '';

		refreshLine(false, false);
	}

	// I controlli confrontano sempre con i dati salvati: se un evento arriva due volte non succede nulla di strano.
	public function UIEvent(id:String, sender:Dynamic)
	{
		if (dialogueFile == null || curSelected >= dialogueFile.dialogue.length)
			return;
		var line:PixelDialogueLine = dialogueFile.dialogue[curSelected];

		if (id == PsychUIInputText.CHANGE_EVENT && (sender is PsychUIInputText))
		{
			if (sender == characterInput)
			{
				if (line.portrait != characterInput.text)
				{
					line.portrait = characterInput.text;
					fixExpression(line);
					refreshLine(true, true);
				}
			}
			else if (sender == expressionInput)
			{
				if (line.expression != expressionInput.text)
				{
					line.expression = expressionInput.text;
					refreshLine(false, true);
				}
			}
			else if (sender == soundInput)
			{
				if (line.sound != soundInput.text)
				{
					line.sound = soundInput.text;
					unsavedProgress = true;
				}
			}
			else if (sender == lineInput)
			{
				if (line.text != lineInput.text)
				{
					line.text = lineInput.text;
					refreshLine(true, true);
				}
			}
			else if (sender == boxInput)
			{
				if (dialogueFile.box != boxInput.text)
				{
					dialogueFile.box = boxInput.text;
					unsavedProgress = true;
					rebuildPreview();
				}
			}
			else if (sender == handInput)
			{
				if (dialogueFile.hand != handInput.text)
				{
					dialogueFile.hand = handInput.text;
					unsavedProgress = true;
					rebuildPreview();
				}
			}
			else if (sender == bgColorInput)
			{
				if (dialogueFile.bgFadeColor != bgColorInput.text)
				{
					dialogueFile.bgFadeColor = bgColorInput.text;
					unsavedProgress = true;
					rebuildPreview();
				}
			}
			else if (sender == textColorInput)
			{
				if (dialogueFile.textColor != textColorInput.text)
				{
					dialogueFile.textColor = textColorInput.text;
					unsavedProgress = true;
					rebuildPreview();
				}
			}
			else if (sender == shadowColorInput)
			{
				if (dialogueFile.shadowColor != shadowColorInput.text)
				{
					dialogueFile.shadowColor = shadowColorInput.text;
					unsavedProgress = true;
					rebuildPreview();
				}
			}
		}
		else if (id == PsychUINumericStepper.CHANGE_EVENT && sender == speedStepper)
		{
			if (line.speed == null || Math.abs(line.speed - speedStepper.value) > 0.0001)
			{
				line.speed = speedStepper.value;
				refreshLine(false, true);
			}
		}
	}

	// ------------------------------------------------------------------
	// Aggiornamento e tasti
	// ------------------------------------------------------------------
	override function update(elapsed:Float)
	{
		if (transitioning)
		{
			super.update(elapsed);
			return;
		}

		if (PsychUIInputText.focusOn == null)
		{
			ClientPrefs.toggleVolumeKeys(true);

			if (FlxG.keys.justPressed.SPACE)
				refreshLine(false, false);

			if (FlxG.keys.justPressed.ESCAPE)
			{
				if (!unsavedProgress)
				{
					MusicBeatState.switchState(new states.editors.MasterEditorMenu());
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					transitioning = true;
				}
				else
					openSubState(new ExitConfirmationPrompt(function() transitioning = true));
				return;
			}

			if (FlxG.keys.justPressed.D)
				changeLine(1);
			if (FlxG.keys.justPressed.A)
				changeLine(-1);
			if (FlxG.keys.justPressed.W)
				cycleExpression(-1);
			if (FlxG.keys.justPressed.S)
				cycleExpression(1);

			if (FlxG.keys.justPressed.O)
			{
				dialogueFile.dialogue.remove(dialogueFile.dialogue[curSelected]);
				if (dialogueFile.dialogue.length < 1) // non lasciare il file vuoto
					dialogueFile.dialogue = [newLine()];
				unsavedProgress = true;
				changeLine(0);
			}
			else if (FlxG.keys.justPressed.P)
			{
				dialogueFile.dialogue.insert(curSelected + 1, copyLine(dialogueFile.dialogue[curSelected]));
				unsavedProgress = true;
				changeLine(1);
			}
		}
		else
			ClientPrefs.toggleVolumeKeys(false);

		super.update(elapsed);
	}

	// ------------------------------------------------------------------
	// Caricamento e salvataggio (stesso meccanismo dell'editor dialoghi HD)
	// ------------------------------------------------------------------
	var _file:FileReference = null;

	function loadDialogue():Void
	{
		var jsonFilter:FileFilter = new FileFilter('JSON', 'json');
		_file = new FileReference();
		_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.addEventListener(Event.CANCEL, onLoadCancel);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file.browse([#if !mac jsonFilter #end]);
	}

	function onLoadComplete(_):Void
	{
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);

		#if sys
		var fullPath:String = null;
		@:privateAccess
		if (_file.__path != null)
			fullPath = _file.__path;

		if (fullPath != null)
		{
			var rawJson:String = File.getContent(fullPath);
			if (rawJson != null)
			{
				if (rawJson.charCodeAt(0) == 0xFEFF)
					rawJson = rawJson.substr(1);

				var loaded:PixelDialogueFile = null;
				try
				{
					loaded = DialogueBoxPixel.normalize(cast Json.parse(rawJson));
				}
				catch (e:Dynamic)
				{
					trace('Invalid file: ' + e);
				}

				if (loaded != null)
				{
					trace("Loaded: " + _file.name);
					dialogueFile = loaded;
					curSelected = 0;
					unsavedProgress = false;
					rebuildPreview();
					changeLine(0);
					_file = null;
					return;
				}
			}
		}
		_file = null;
		#else
		trace("File couldn't be loaded! You aren't on Desktop, are you?");
		#end
	}

	function onLoadCancel(_):Void
	{
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file = null;
		trace("Cancelled file loading.");
	}

	function onLoadError(_):Void
	{
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file = null;
		trace("Problem loading file");
	}

	function saveDialogue():Void
	{
		var data:String = haxe.Json.stringify(dialogueFile, "\t");
		if (data.length > 0)
		{
			#if mobile
			unsavedProgress = false;
			StorageUtil.saveContent("dialogue-pixel.json", data);
			#else
			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data, "dialogue-pixel.json");
			#end
		}
	}

	function onSaveComplete(_):Void
	{
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		unsavedProgress = false;
		FlxG.log.notice("Successfully saved file.");
	}

	function onSaveCancel(_):Void
	{
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
	}

	function onSaveError(_):Void
	{
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.error("Problem saving file");
	}
}
