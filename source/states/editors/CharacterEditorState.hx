package states.editors;

import flixel.graphics.frames.FlxAtlasFrames;
import flixel.util.FlxDestroyUtil;
import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.events.MouseEvent;
import openfl.geom.Point;
import objects.Character;
import objects.HealthIcon;
import objects.Bar;
import states.stages.StageWeek1 as BackgroundStage;
import states.editors.content.Prompt;
import states.editors.content.PsychJsonPrinter;
#if MODS_ALLOWED
import sys.io.File;
#end

class CharacterEditorState extends MusicBeatState implements PsychUIEventHandler.PsychUIEvent
{
	var character:Character;
	var ghost:FlxSprite;
	var animateGhost:FlxAnimate;
	var animateGhostImage:String;
	var cameraFollowPointer:FlxSprite;
	var isAnimateSprite:Bool = false;

	var silhouettes:FlxSpriteGroup;
	var dadPosition = FlxPoint.weak();
	var bfPosition = FlxPoint.weak();

	var helpBg:FlxSprite;
	var helpTexts:FlxSpriteGroup;
	var cameraZoomText:FlxText;
	var frameAdvanceText:FlxText;

	var healthBar:Bar;
	var healthIcon:HealthIcon;

	var copiedOffset:Array<Float> = [0, 0];
	var _char:String = null;
	var _goToPlayState:Bool = true;

	var anims = null;
	var animsTxt:FlxText;
	var curAnim = 0;

	private var camEditor:FlxCamera;
	private var camHUD:FlxCamera;

	var UI_box:PsychUIBox;
	var UI_characterbox:PsychUIBox;

	var unsavedProgress:Bool = false;

	var selectedFormat:FlxTextFormat = new FlxTextFormat(FlxColor.LIME);

	var cameraPosition:Point = new Point();
	var isDragging:Bool = false;
	var draggingCharacter:Bool = false;

	public function new(char:String = null, goToPlayState:Bool = true)
	{
		this._char = char;
		this._goToPlayState = goToPlayState;
		if (this._char == null)
			this._char = Character.DEFAULT_CHARACTER;

		super();
	}

	override function create()
	{
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();

		FlxG.sound.music.stop();
		camEditor = initPsychCamera();

		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.add(camHUD, false);

		loadBG();

		silhouettes = new FlxSpriteGroup();
		add(silhouettes);

		var dad:FlxSprite = new FlxSprite(dadPosition.x, dadPosition.y).loadGraphic(Paths.image('editors/silhouetteDad'));
		dad.antialiasing = ClientPrefs.data.antialiasing;
		dad.active = false;
		dad.offset.set(-4, 1);
		silhouettes.add(dad);

		var boyfriend:FlxSprite = new FlxSprite(bfPosition.x, bfPosition.y + 350).loadGraphic(Paths.image('editors/silhouetteBF'));
		boyfriend.antialiasing = ClientPrefs.data.antialiasing;
		boyfriend.active = false;
		boyfriend.offset.set(-6, 2);
		silhouettes.add(boyfriend);

		silhouettes.alpha = 0.25;

		ghost = new FlxSprite();
		ghost.visible = false;
		ghost.alpha = ghostAlpha;
		add(ghost);

		animsTxt = new FlxText(10, 32, 400, '');
		animsTxt.setFormat(null, 16, FlxColor.WHITE, LEFT, OUTLINE_FAST, FlxColor.BLACK);
		animsTxt.scrollFactor.set();
		animsTxt.borderSize = 1;
		animsTxt.cameras = [camHUD];

		addCharacter();

		cameraFollowPointer = new FlxSprite().makeGraphic(6, 6, FlxColor.LIME);
		cameraFollowPointer.alpha = controls.mobileC ? 0.25 : 0.45;

		healthBar = new Bar(30, FlxG.height - 75);
		healthBar.scrollFactor.set();
		healthBar.cameras = [camHUD];

		healthIcon = new HealthIcon(character.healthIcon, false, false);
		healthIcon.y = FlxG.height - 150;
		healthIcon.cameras = [camHUD];

		add(cameraFollowPointer);
		add(healthBar);
		add(healthIcon);
		add(animsTxt);

		var tipText:FlxText = new FlxText(FlxG.width - 300, FlxG.height - 24, 300, 'Press ${(controls.mobileC) ? 'F' : 'F1'} for Help', 20);
		tipText.cameras = [camHUD];
		tipText.setFormat(null, 16, FlxColor.WHITE, RIGHT, OUTLINE_FAST, FlxColor.BLACK);
		tipText.borderColor = FlxColor.BLACK;
		tipText.scrollFactor.set();
		tipText.borderSize = 1;
		tipText.active = false;
		add(tipText);

		cameraZoomText = new FlxText(0, 50, 200, 'Zoom: 1x');
		cameraZoomText.setFormat(null, 16, FlxColor.WHITE, CENTER, OUTLINE_FAST, FlxColor.BLACK);
		cameraZoomText.scrollFactor.set();
		cameraZoomText.borderSize = 1;
		cameraZoomText.screenCenter(X);
		cameraZoomText.cameras = [camHUD];
		add(cameraZoomText);

		frameAdvanceText = new FlxText(0, 75, 350, '');
		frameAdvanceText.setFormat(null, 16, FlxColor.WHITE, CENTER, OUTLINE_FAST, FlxColor.BLACK);
		frameAdvanceText.scrollFactor.set();
		frameAdvanceText.borderSize = 1;
		frameAdvanceText.screenCenter(X);
		frameAdvanceText.cameras = [camHUD];
		add(frameAdvanceText);

		addHelpScreen();
		FlxG.mouse.visible = true;
		FlxG.camera.zoom = 1;

		makeUIMenu();
		addXmlPicker();

		updatePointerPos();
		updateHealthBar();
		character.finishAnimation();

		addTouchPad('LEFT_FULL', 'CHARACTER_EDITOR');
		addTouchPadCamera();

		if (controls.mobileC)
		{
			FlxG.stage.addEventListener(MouseEvent.MOUSE_DOWN, onMouseEvent);
			FlxG.stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseEvent);
			FlxG.stage.addEventListener(MouseEvent.MOUSE_UP, onMouseEvent);
		}

		if (ClientPrefs.data.cacheOnGPU)
			Paths.clearUnusedMemory();

		super.create();
	}

	function addHelpScreen()
	{
		var str:Array<String> = (controls.mobileC) ? [
			"CAMERA",
			"X/Y - Camera Zoom In/Out",
			"G + Arrow Buttons - Move Camera",
			"Z - Reset Camera Zoom",
			"",
			"CHARACTER",
			"A - Reset Current Offset",
			"V/D - Previous/Next Animation",
			"Arrow Buttons - Move Offset",
			"",
			"OTHER",
			"S - Toggle Silhouettes",
			"Hold C - Move Offsets 10x faster and Camera 4x faster"
		] : [
			"CAMERA",
			"E/Q - Camera Zoom In/Out",
			"J/K/L/I - Move Camera",
			"R - Reset Camera Zoom",
			"",
			"CHARACTER",
			"Ctrl + R - Reset Current Offset",
			"Ctrl + C - Copy Current Offset",
			"Ctrl + V - Paste Copied Offset on Current Animation",
			"Ctrl + Z - Undo Last Paste or Reset",
			"W/S - Previous/Next Animation",
			"Space - Replay Animation",
			"Arrow Keys - Move Offset",
			"Ctrl + Left Click & Drag - Move Offset (even if you miss the character)",
			"Right Click & Drag - Move Offset (hold Ctrl for precision)",
			"Alt + Left Click & Drag - Move the whole Character (position)",
			"A/D - Frame Advance (Back/Forward)",
			"",
			"OTHER",
			"F12 - Toggle Silhouettes",
			"Hold Shift - Move Offsets 10x faster and Camera 4x faster",
			"Hold Control - Move camera 4x slower"
		];

		helpBg = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		helpBg.scale.set(FlxG.width, FlxG.height);
		helpBg.updateHitbox();
		helpBg.alpha = 0.6;
		helpBg.cameras = [camHUD];
		helpBg.active = helpBg.visible = false;
		add(helpBg);

		helpTexts = new FlxSpriteGroup();
		helpTexts.cameras = [camHUD];
		for (i => txt in str)
		{
			if (txt.length < 1)
				continue;

			var helpText:FlxText = new FlxText(0, 0, 600, txt, 16);
			helpText.setFormat(null, 16, FlxColor.WHITE, CENTER, OUTLINE_FAST, FlxColor.BLACK);
			helpText.borderColor = FlxColor.BLACK;
			helpText.scrollFactor.set();
			helpText.borderSize = 1;
			helpText.screenCenter();
			add(helpText);
			helpText.y += ((i - str.length / 2) * 32) + 16;
			helpText.active = false;
			helpTexts.add(helpText);
		}
		helpTexts.active = helpTexts.visible = false;
		add(helpTexts);
	}

	function addCharacter(reload:Bool = false)
	{
		var pos:Int = -1;
		var keepAnimatedIcon:Null<Bool> = null;
		if (character != null)
		{
			pos = members.indexOf(character);
			if (reload && animatedIconCheckBox != null)
				keepAnimatedIcon = animatedIconCheckBox.checked;
			remove(character);
			character.destroy();
		}

		var isPlayer = (reload ? character.isPlayer : !predictCharacterIsNotPlayer(_char));
		character = new Character(0, 0, _char, isPlayer);

		if (keepAnimatedIcon != null)
			character.animatedIcon = keepAnimatedIcon;

		if (!reload && character.editorIsPlayer != null && isPlayer != character.editorIsPlayer)
		{
			character.isPlayer = !character.isPlayer;
			character.flipX = (character.originalFlipX != character.isPlayer);
		}
		if (check_player != null)
			check_player.checked = character.isPlayer;

		character.debugMode = true;
		character.missingCharacter = false;

		if (pos > -1)
			insert(pos, character);
		else
			add(character);
		updateCharacterPositions();
		reloadAnimList();
		if (healthBar != null && healthIcon != null)
			updateHealthBar();
	}

	function makeUIMenu()
	{
		UI_box = new PsychUIBox(FlxG.width - 275, 25, 250, 120, ['Ghost', 'Settings']);
		UI_box.scrollFactor.set();
		UI_box.cameras = [camHUD];

		UI_characterbox = new PsychUIBox(UI_box.x - 100, UI_box.y + UI_box.height + 10, 350, 280, ['Animations', 'Character']);
		UI_characterbox.scrollFactor.set();
		UI_characterbox.cameras = [camHUD];
		add(UI_characterbox);
		add(UI_box);

		addGhostUI();
		addSettingsUI();
		addAnimationsUI();
		addCharacterUI();

		UI_box.selectedName = 'Settings';
		UI_characterbox.selectedName = 'Character';
	}

	var ghostAlpha:Float = 0.6;

	function addGhostUI()
	{
		var tab_group = UI_box.getTab('Ghost').menu;

		var makeGhostButton:PsychUIButton = new PsychUIButton(25, 15, "Make Ghost", function()
		{
			var anim = anims[curAnim];
			if (!character.isAnimationNull())
			{
				var myAnim = anims[curAnim];
				if (!character.isAnimateAtlas)
				{
					ghost.loadGraphic(character.graphic);
					ghost.frames.frames = character.frames.frames;
					ghost.animation.copyFrom(character.animation);
					ghost.animation.play(character.animation.curAnim.name, true, false, character.animation.curAnim.curFrame);
					ghost.animation.pause();
				}
				else
					if (myAnim != null)
				{
					if (animateGhost == null)
					{
						animateGhost = new FlxAnimate(ghost.x, ghost.y);
						animateGhost.showPivot = false;
						insert(members.indexOf(ghost), animateGhost);
						animateGhost.active = false;
					}

					if (animateGhost == null || animateGhostImage != character.imageFile)
						Paths.loadAnimateAtlas(animateGhost, character.imageFile);

					if (myAnim.indices != null && myAnim.indices.length > 0)
						animateGhost.anim.addBySymbolIndices('anim', myAnim.name, myAnim.indices, 0, false);
					else
						animateGhost.anim.addBySymbol('anim', myAnim.name, 0, false);

					animateGhost.anim.play('anim', true, false, character.atlas.anim.curFrame);
					animateGhost.anim.pause();

					animateGhostImage = character.imageFile;
				}

				var spr:FlxSprite = !character.isAnimateAtlas ? ghost : animateGhost;
				if (spr != null)
				{
					spr.setPosition(character.x, character.y);
					spr.antialiasing = character.antialiasing;
					spr.flipX = character.flipX;
					spr.alpha = ghostAlpha;

					spr.scale.set(character.scale.x, character.scale.y);
					spr.updateHitbox();

					spr.offset.set(character.offset.x, character.offset.y);
					spr.visible = true;

					var otherSpr:FlxSprite = (spr == animateGhost) ? ghost : animateGhost;
					if (otherSpr != null)
						otherSpr.visible = false;
				}
				trace('created ghost image');
			}
		});

		var highlightGhost:PsychUICheckBox = new PsychUICheckBox(20 + makeGhostButton.x + makeGhostButton.width, makeGhostButton.y, "Highlight Ghost", 100);
		highlightGhost.onClick = function()
		{
			var value = highlightGhost.checked ? 125 : 0;
			ghost.colorTransform.redOffset = value;
			ghost.colorTransform.greenOffset = value;
			ghost.colorTransform.blueOffset = value;
			if (animateGhost != null)
			{
				animateGhost.colorTransform.redOffset = value;
				animateGhost.colorTransform.greenOffset = value;
				animateGhost.colorTransform.blueOffset = value;
			}
		};

		var ghostAlphaSlider:PsychUISlider = new PsychUISlider(15, makeGhostButton.y + 25, function(v:Float)
		{
			ghostAlpha = v;
			ghost.alpha = ghostAlpha;
			if (animateGhost != null)
				animateGhost.alpha = ghostAlpha;
		}, ghostAlpha, 0, 1);
		ghostAlphaSlider.label = 'Opacity:';

		tab_group.add(makeGhostButton);
		tab_group.add(highlightGhost);
		tab_group.add(ghostAlphaSlider);
	}

	var check_player:PsychUICheckBox;
	var charDropDown:PsychUIDropDownMenu;

	function addSettingsUI()
	{
		var tab_group = UI_box.getTab('Settings').menu;

		check_player = new PsychUICheckBox(10, 60, "Playable Character", 100);
		check_player.checked = character.isPlayer;
		check_player.onClick = function()
		{
			character.isPlayer = !character.isPlayer;
			character.flipX = !character.flipX;
			updateCharacterPositions();
			updatePointerPos(false);
		};

		var reloadCharacter:PsychUIButton = new PsychUIButton(140, 20, "Reload Char", function()
		{
			addCharacter(true);
			updatePointerPos();
			reloadCharacterOptions();
			reloadCharacterDropDown();
		});

		var templateCharacter:PsychUIButton = new PsychUIButton(140, 50, "Load Template", function()
		{
			final _template:CharacterFile = {
				animations: [
					newAnim('idle', 'BF idle dance'),
					newAnim('singLEFT', 'BF NOTE LEFT0'),
					newAnim('singDOWN', 'BF NOTE DOWN0'),
					newAnim('singUP', 'BF NOTE UP0'),
					newAnim('singRIGHT', 'BF NOTE RIGHT0')
				],
				no_antialiasing: false,
				flip_x: false,
				healthicon: 'face',
				image: 'characters/BOYFRIEND',
				sing_duration: 4,
				scale: 1,
				healthbar_colors: [161, 161, 161],
				camera_position: [0, 0],
				position: [0, 0],
				vocals_file: null
			};

			character.loadCharacterFile(_template);
			character.missingCharacter = false;
			character.color = FlxColor.WHITE;
			character.alpha = 1;
			reloadAnimList();
			reloadCharacterOptions();
			updateCharacterPositions();
			updatePointerPos();
			reloadCharacterDropDown();
			updateHealthBar();
		});
		templateCharacter.normalStyle.bgColor = FlxColor.RED;
		templateCharacter.normalStyle.textColor = FlxColor.WHITE;

		charDropDown = new PsychUIDropDownMenu(10, 30, [''], function(index:Int, intended:String)
		{
			if (intended == null || intended.length < 1)
				return;

			var characterPath:String = 'characters/$intended.json';
			var path:String = Paths.getPath(characterPath, TEXT, null, true);
			#if MODS_ALLOWED
			if (FileSystem.exists(path))
			#else
			if (Assets.exists(path))
			#end
			{
				_char = intended;
				check_player.checked = character.isPlayer;
				addCharacter();
				reloadCharacterOptions();
				reloadCharacterDropDown();
				updatePointerPos();
			}
		else
		{
			reloadCharacterDropDown();
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
		});
		reloadCharacterDropDown();
		charDropDown.selectedLabel = _char;

		tab_group.add(new FlxText(charDropDown.x, charDropDown.y - 18, 80, 'Character:'));
		tab_group.add(check_player);
		tab_group.add(reloadCharacter);
		tab_group.add(templateCharacter);
		tab_group.add(charDropDown);
	}

	var animationDropDown:PsychUIDropDownMenu;
	var animationInputText:PsychUIInputText;
	var animationNameInputText:PsychUIInputText;
	var animationIndicesInputText:PsychUIInputText;
	var animationFramerate:PsychUINumericStepper;
	var animationLoopCheckBox:PsychUICheckBox;

	function addAnimationsUI()
	{
		var tab_group = UI_characterbox.getTab('Animations').menu;

		animationInputText = new PsychUIInputText(15, 85, 80, '', 8);
		animationNameInputText = new PsychUIInputText(animationInputText.x, animationInputText.y + 35, 150, '', 8);
		animationIndicesInputText = new PsychUIInputText(animationNameInputText.x, animationNameInputText.y + 40, 250, '', 8);
		animationFramerate = new PsychUINumericStepper(animationInputText.x + 170, animationInputText.y, 1, 24, 0, 240, 0);
		animationLoopCheckBox = new PsychUICheckBox(animationNameInputText.x + 170, animationNameInputText.y - 1, "Should it Loop?", 100);

		animationDropDown = new PsychUIDropDownMenu(15, animationInputText.y - 55, [''], function(selectedAnimation:Int, pressed:String)
		{
			var anim:AnimArray = character.animationsArray[selectedAnimation];
			animationInputText.text = anim.anim;
			animationNameInputText.text = anim.name;
			animationLoopCheckBox.checked = anim.loop;
			animationFramerate.value = anim.fps;

			var indicesStr:String = anim.indices.toString();
			animationIndicesInputText.text = indicesStr.substr(1, indicesStr.length - 2);
		});

		var addUpdateButton:PsychUIButton = new PsychUIButton(70, animationIndicesInputText.y + 60, "Add/Update", function()
		{
			var indicesText:String = animationIndicesInputText.text.trim();
			var indices:Array<Int> = [];
			if (indicesText.length > 0)
			{
				var indicesStr:Array<String> = animationIndicesInputText.text.trim().split(',');
				if (indicesStr.length > 0)
				{
					for (ind in indicesStr)
					{
						if (ind.contains('-'))
						{
							var splitIndices:Array<String> = ind.split('-');
							var indexStart:Int = Std.parseInt(splitIndices[0]);
							if (Math.isNaN(indexStart) || indexStart < 0)
								indexStart = 0;

							var indexEnd:Int = Std.parseInt(splitIndices[1]);
							if (Math.isNaN(indexEnd) || indexEnd < indexStart)
								indexEnd = indexStart;

							for (index in indexStart...indexEnd + 1)
								indices.push(index);
						}
						else
						{
							var index:Int = Std.parseInt(ind);
							if (!Math.isNaN(index) && index > -1)
								indices.push(index);
						}
					}
				}
			}

			var lastAnim:String = (character.animationsArray[curAnim] != null) ? character.animationsArray[curAnim].anim : '';
			var lastOffsets:Array<Int> = [0, 0];
			for (anim in character.animationsArray)
				if (animationInputText.text == anim.anim)
				{
					lastOffsets = anim.offsets;
					if (character.hasAnimation(animationInputText.text))
					{
						if (!character.isAnimateAtlas)
							character.animation.remove(animationInputText.text);
						else
							@:privateAccess character.atlas.anim.animsMap.remove(animationInputText.text);
					}
					character.animationsArray.remove(anim);
				}

			var addedAnim:AnimArray = newAnim(animationInputText.text, animationNameInputText.text);
			addedAnim.fps = Math.round(animationFramerate.value);
			addedAnim.loop = animationLoopCheckBox.checked;
			addedAnim.indices = indices;
			addedAnim.offsets = lastOffsets;
			addAnimation(addedAnim.anim, addedAnim.name, addedAnim.fps, addedAnim.loop, addedAnim.indices);
			character.animationsArray.push(addedAnim);

			reloadAnimList();
			@:arrayAccess curAnim = Std.int(Math.max(0, character.animationsArray.indexOf(addedAnim)));
			character.playAnim(addedAnim.anim, true);
			trace('Added/Updated animation: ' + animationInputText.text);
		});

		var removeButton:PsychUIButton = new PsychUIButton(180, animationIndicesInputText.y + 60, "Remove", function()
		{
			for (anim in character.animationsArray)
				if (animationInputText.text == anim.anim)
				{
					var resetAnim:Bool = false;
					if (anim.anim == character.getAnimationName())
						resetAnim = true;
					if (character.hasAnimation(anim.anim))
					{
						if (!character.isAnimateAtlas)
							character.animation.remove(anim.anim);
						else
							@:privateAccess character.atlas.anim.animsMap.remove(anim.anim);
						character.animOffsets.remove(anim.anim);
						character.animationsArray.remove(anim);
					}

					if (resetAnim && character.animationsArray.length > 0)
					{
						curAnim = FlxMath.wrap(curAnim, 0, anims.length - 1);
						character.playAnim(anims[curAnim].anim, true);
					}
					reloadAnimList();
					trace('Removed animation: ' + animationInputText.text);
					break;
				}
		});
		reloadAnimList();
		animationDropDown.selectedLabel = anims[0] != null ? anims[0].anim : '';

		tab_group.add(new FlxText(animationDropDown.x, animationDropDown.y - 18, 100, 'Animations:'));
		tab_group.add(new FlxText(animationInputText.x, animationInputText.y - 18, 100, 'Animation name:'));
		tab_group.add(new FlxText(animationFramerate.x, animationFramerate.y - 18, 100, 'Framerate:'));
		tab_group.add(new FlxText(animationNameInputText.x, animationNameInputText.y - 18, 150, 'Animation Symbol Name/Tag:'));
		tab_group.add(new FlxText(animationIndicesInputText.x, animationIndicesInputText.y - 18, 170, 'ADVANCED - Animation Indices:'));

		tab_group.add(animationInputText);
		tab_group.add(animationNameInputText);
		tab_group.add(animationIndicesInputText);
		tab_group.add(animationFramerate);
		tab_group.add(animationLoopCheckBox);
		tab_group.add(addUpdateButton);
		tab_group.add(removeButton);
		tab_group.add(animationDropDown);
	}

	var imageInputText:PsychUIInputText;
	var healthIconInputText:PsychUIInputText;
	var vocalsInputText:PsychUIInputText;

	var singDurationStepper:PsychUINumericStepper;
	var scaleStepper:PsychUINumericStepper;
	var positionXStepper:PsychUINumericStepper;
	var positionYStepper:PsychUINumericStepper;
	var positionCameraXStepper:PsychUINumericStepper;
	var positionCameraYStepper:PsychUINumericStepper;

	var flipXCheckBox:PsychUICheckBox;
	var noAntialiasingCheckBox:PsychUICheckBox;
	var animatedIconCheckBox:PsychUICheckBox;

	var healthColorStepperR:PsychUINumericStepper;
	var healthColorStepperG:PsychUINumericStepper;
	var healthColorStepperB:PsychUINumericStepper;

	function addCharacterUI()
	{
		var tab_group = UI_characterbox.getTab('Character').menu;

		imageInputText = new PsychUIInputText(15, 30, 200, character.imageFile, 8);
		var reloadImage:PsychUIButton = new PsychUIButton(imageInputText.x + 210, imageInputText.y - 3, "Reload Image", function()
		{
			var lastAnim = character.getAnimationName();
			character.imageFile = imageInputText.text;
			reloadCharacterImage();
			if (!character.isAnimationNull())
			{
				character.playAnim(lastAnim, true);
			}
		});

		var decideIconColor:PsychUIButton = new PsychUIButton(reloadImage.x, reloadImage.y + 30, "Get Icon Color", function()
		{
			var coolColor:FlxColor = FlxColor.fromInt(CoolUtil.dominantColor(healthIcon));
			character.healthColorArray[0] = coolColor.red;
			character.healthColorArray[1] = coolColor.green;
			character.healthColorArray[2] = coolColor.blue;
			updateHealthBar();
		});

		var animsFromXml:PsychUIButton = new PsychUIButton(reloadImage.x, decideIconColor.y + 33, "Anims from XML", function()
		{
			openXmlPicker();
		}, 110);
		animsFromXml.normalStyle.bgColor = FlxColor.fromRGB(40, 140, 70);
		animsFromXml.normalStyle.textColor = FlxColor.WHITE;

		healthIconInputText = new PsychUIInputText(15, imageInputText.y + 35, 75, healthIcon.getCharacter(), 8);

		animatedIconCheckBox = new PsychUICheckBox(healthIconInputText.x + 85, healthIconInputText.y + 2, "Animated Icon", 120);
		animatedIconCheckBox.checked = character.animatedIcon == true;
		animatedIconCheckBox.onClick = function()
		{
			character.animatedIcon = animatedIconCheckBox.checked;
			healthIcon.changeIcon(character.healthIcon, false, character.animatedIcon);
		};

		vocalsInputText = new PsychUIInputText(15, healthIconInputText.y + 35, 75, character.vocalsFile != null ? character.vocalsFile : '', 8);

		singDurationStepper = new PsychUINumericStepper(15, vocalsInputText.y + 45, 0.1, 4, 0, 999, 1);

		scaleStepper = new PsychUINumericStepper(15, singDurationStepper.y + 40, 0.1, 1, 0.05, 10, 2);

		flipXCheckBox = new PsychUICheckBox(singDurationStepper.x + 80, singDurationStepper.y, "Flip X", 50);
		flipXCheckBox.checked = character.flipX;
		if (character.isPlayer)
			flipXCheckBox.checked = !flipXCheckBox.checked;
		flipXCheckBox.onClick = function()
		{
			character.originalFlipX = !character.originalFlipX;
			character.flipX = (character.originalFlipX != character.isPlayer);
		};

		noAntialiasingCheckBox = new PsychUICheckBox(flipXCheckBox.x, flipXCheckBox.y + 40, "No Antialiasing", 80);
		noAntialiasingCheckBox.checked = character.noAntialiasing;
		noAntialiasingCheckBox.onClick = function()
		{
			character.antialiasing = false;
			if (!noAntialiasingCheckBox.checked && ClientPrefs.data.antialiasing)
			{
				character.antialiasing = true;
			}
			character.noAntialiasing = noAntialiasingCheckBox.checked;
		};

		positionXStepper = new PsychUINumericStepper(flipXCheckBox.x + 110, flipXCheckBox.y, 10, character.positionArray[0], -9000, 9000, 0);
		positionYStepper = new PsychUINumericStepper(positionXStepper.x + 70, positionXStepper.y, 10, character.positionArray[1], -9000, 9000, 0);

		positionCameraXStepper = new PsychUINumericStepper(positionXStepper.x, positionXStepper.y + 40, 10, character.cameraPosition[0], -9000, 9000, 0);
		positionCameraYStepper = new PsychUINumericStepper(positionYStepper.x, positionYStepper.y + 40, 10, character.cameraPosition[1], -9000, 9000, 0);

		var saveCharacterButton:PsychUIButton = new PsychUIButton(reloadImage.x, noAntialiasingCheckBox.y + 40, "Save Character", function()
		{
			saveCharacter();
		});

		healthColorStepperR = new PsychUINumericStepper(singDurationStepper.x, saveCharacterButton.y, 20, character.healthColorArray[0], 0, 255, 0);
		healthColorStepperG = new PsychUINumericStepper(singDurationStepper.x + 65, saveCharacterButton.y, 20, character.healthColorArray[1], 0, 255, 0);
		healthColorStepperB = new PsychUINumericStepper(singDurationStepper.x + 130, saveCharacterButton.y, 20, character.healthColorArray[2], 0, 255, 0);

		tab_group.add(new FlxText(15, imageInputText.y - 18, 100, 'Image file name:'));
		tab_group.add(new FlxText(15, healthIconInputText.y - 18, 100, 'Health icon name:'));
		tab_group.add(new FlxText(15, vocalsInputText.y - 18, 100, 'Vocals File Postfix:'));
		tab_group.add(new FlxText(15, singDurationStepper.y - 18, 120, 'Sing Animation length:'));
		tab_group.add(new FlxText(15, scaleStepper.y - 18, 100, 'Scale:'));
		tab_group.add(new FlxText(positionXStepper.x, positionXStepper.y - 18, 100, 'Character X/Y:'));
		tab_group.add(new FlxText(positionCameraXStepper.x, positionCameraXStepper.y - 18, 100, 'Camera X/Y:'));
		tab_group.add(new FlxText(healthColorStepperR.x, healthColorStepperR.y - 18, 100, 'Health Bar R/G/B:'));
		tab_group.add(imageInputText);
		tab_group.add(reloadImage);
		tab_group.add(decideIconColor);
		tab_group.add(animsFromXml);
		tab_group.add(healthIconInputText);
		tab_group.add(animatedIconCheckBox);
		tab_group.add(vocalsInputText);
		tab_group.add(singDurationStepper);
		tab_group.add(scaleStepper);
		tab_group.add(flipXCheckBox);
		tab_group.add(noAntialiasingCheckBox);
		tab_group.add(positionXStepper);
		tab_group.add(positionYStepper);
		tab_group.add(positionCameraXStepper);
		tab_group.add(positionCameraYStepper);
		tab_group.add(healthColorStepperR);
		tab_group.add(healthColorStepperG);
		tab_group.add(healthColorStepperB);
		tab_group.add(saveCharacterButton);
	}

	public function UIEvent(id:String, sender:Dynamic)
	{
		if (id == PsychUICheckBox.CLICK_EVENT)
			unsavedProgress = true;

		if (id == PsychUIInputText.CHANGE_EVENT)
		{
			if (sender == healthIconInputText)
			{
				var lastIcon = healthIcon.getCharacter();
				healthIcon.changeIcon(healthIconInputText.text, false, character.animatedIcon == true);
				character.healthIcon = healthIconInputText.text;
				if (lastIcon != healthIcon.getCharacter())
					updatePresence();
				unsavedProgress = true;
			}
			else if (sender == vocalsInputText)
			{
				character.vocalsFile = vocalsInputText.text;
				unsavedProgress = true;
			}
			else if (sender == imageInputText)
			{
				character.imageFile = imageInputText.text;
				unsavedProgress = true;
			}
		}
		else if (id == PsychUINumericStepper.CHANGE_EVENT)
		{
			if (sender == scaleStepper)
			{
				reloadCharacterImage();
				character.jsonScale = sender.value;
				character.scale.set(character.jsonScale, character.jsonScale);
				character.updateHitbox();
				updatePointerPos(false);
				unsavedProgress = true;
			}
			else if (sender == positionXStepper)
			{
				character.positionArray[0] = positionXStepper.value;
				updateCharacterPositions();
				unsavedProgress = true;
			}
			else if (sender == positionYStepper)
			{
				character.positionArray[1] = positionYStepper.value;
				updateCharacterPositions();
				unsavedProgress = true;
			}
			else if (sender == singDurationStepper)
			{
				character.singDuration = singDurationStepper.value;
				unsavedProgress = true;
			}
			else if (sender == positionCameraXStepper)
			{
				character.cameraPosition[0] = positionCameraXStepper.value;
				updatePointerPos();
				unsavedProgress = true;
			}
			else if (sender == positionCameraYStepper)
			{
				character.cameraPosition[1] = positionCameraYStepper.value;
				updatePointerPos();
				unsavedProgress = true;
			}
			else if (sender == healthColorStepperR)
			{
				character.healthColorArray[0] = Math.round(healthColorStepperR.value);
				updateHealthBar();
				unsavedProgress = true;
			}
			else if (sender == healthColorStepperG)
			{
				character.healthColorArray[1] = Math.round(healthColorStepperG.value);
				updateHealthBar();
				unsavedProgress = true;
			}
			else if (sender == healthColorStepperB)
			{
				character.healthColorArray[2] = Math.round(healthColorStepperB.value);
				updateHealthBar();
				unsavedProgress = true;
			}
		}
	}

	function reloadCharacterImage()
	{
		var lastAnim:String = character.getAnimationName();
		var anims:Array<AnimArray> = character.animationsArray.copy();

		character.atlas = FlxDestroyUtil.destroy(character.atlas);
		character.isAnimateAtlas = false;
		character.color = FlxColor.WHITE;
		character.alpha = 1;

		var useAnimateAtlas:Bool = Character.usesAnimateAtlas(character.renderType) || (character.renderType == 'sparrow' && Paths.hasAnimateAtlas(character.imageFile));
		if (useAnimateAtlas)
		{
			character.atlas = new FlxAnimate();
			character.atlas.showPivot = false;
			try
			{
				Paths.loadAnimateAtlas(character.atlas, getEditorAnimateAtlasKeys(anims));
			}
			catch (e:Dynamic)
			{
				FlxG.log.warn('Could not load atlas ${character.imageFile}: $e');
			}
			character.isAnimateAtlas = true;
			character.frames = getEditorClassicFrames(anims, false);
		}
		else
		{
			character.frames = getEditorClassicFrames(anims, true);
		}

		for (anim in anims)
		{
			var animAnim:String = '' + anim.anim;
			var animName:String = '' + anim.name;
			var animFps:Int = anim.fps;
			var animLoop:Bool = !!anim.loop;
			var animIndices:Array<Int> = anim.indices;
			addAnimation(animAnim, animName, animFps, animLoop, animIndices, anim.animType, anim.renderType);
		}

		if (anims.length > 0)
		{
			if (lastAnim != '')
				character.playAnim(lastAnim, true);
			else
				character.dance();
		}
	}

	function reloadCharacterOptions()
	{
		if (UI_characterbox == null)
			return;

		check_player.checked = character.isPlayer;
		imageInputText.text = character.imageFile;
		healthIconInputText.text = character.healthIcon;
		vocalsInputText.text = character.vocalsFile != null ? character.vocalsFile : '';
		singDurationStepper.value = character.singDuration;
		scaleStepper.value = character.jsonScale;
		flipXCheckBox.checked = character.originalFlipX;
		noAntialiasingCheckBox.checked = character.noAntialiasing;
		positionXStepper.value = character.positionArray[0];
		positionYStepper.value = character.positionArray[1];
		positionCameraXStepper.value = character.cameraPosition[0];
		positionCameraYStepper.value = character.cameraPosition[1];

		animatedIconCheckBox.checked = character.animatedIcon == true;
		reloadAnimationDropDown();
		updateHealthBar();
	}

	var holdingArrowsTime:Float = 0;
	var holdingArrowsElapsed:Float = 0;
	var holdingFrameTime:Float = 0;
	var holdingFrameElapsed:Float = 0;
	var undoOffsets:Array<Float> = null;

	function handleMouseDrag():Void
	{
		if (character == null || character.scale.x == 0 || character.scale.y == 0)
			return;

		if (!draggingCharacter)
		{
			if (ctrlDragging || altDragging || FlxG.keys.pressed.CONTROL || FlxG.keys.pressed.ALT)
				return;
			if (!isMouseOverUI() && FlxG.mouse.justPressed && FlxG.mouse.overlaps(character, camEditor))
				draggingCharacter = true;
			return;
		}

		var anim:AnimArray = (curAnim >= 0 && curAnim < anims.length) ? anims[curAnim] : null;
		if (anim == null || anim.offsets == null)
		{
			draggingCharacter = false;
			return;
		}

		var zoom:Float = FlxG.camera.zoom;
		if (zoom <= 0) zoom = 1;

		var dx:Float = (FlxG.mouse.deltaScreenX / zoom) / character.scale.x;
		var dy:Float = (FlxG.mouse.deltaScreenY / zoom) / character.scale.y;

		if (character.flipX)
			dx *= -1;

		character.offset.x -= dx;
		character.offset.y -= dy;

		anim.offsets[0] = Std.int(character.offset.x);
		anim.offsets[1] = Std.int(character.offset.y);

		character.addOffset(anim.anim, character.offset.x, character.offset.y);
		updateText();

		if (FlxG.mouse.justReleased)
			draggingCharacter = false;
	}

	// ---- Ctrl + drag logic (same as the Stage Editor) ----
	var ctrlDragging:Bool = false;
	var ctrlGrabWorldX:Float = 0;
	var ctrlGrabWorldY:Float = 0;
	var ctrlGrabOffsetX:Float = 0;
	var ctrlGrabOffsetY:Float = 0;
	// Alt + drag = move the whole character (its position, not the animation offset)
	var altDragging:Bool = false;
	var altGrabWorldX:Float = 0;
	var altGrabWorldY:Float = 0;
	var altGrabPosX:Float = 0;
	var altGrabPosY:Float = 0;
	var rightAccX:Float = 0;
	var rightAccY:Float = 0;
	var rightDownOnUI:Bool = false;
	final _mousePoint:FlxPoint = FlxPoint.get();

	// Mouse position in the "space" of a sprite with a given scrollFactor.
	// Zoom centered on the camera center: x = scroll*sf + size/2 + (screen - size/2) / zoom
	function mouseToSpriteSpace(spr:FlxSprite, out:FlxPoint):FlxPoint
	{
		var cam:FlxCamera = FlxG.camera;
		out.x = cam.scroll.x * spr.scrollFactor.x + cam.width / 2 + (FlxG.mouse.screenX - cam.width / 2) / cam.zoom;
		out.y = cam.scroll.y * spr.scrollFactor.y + cam.height / 2 + (FlxG.mouse.screenY - cam.height / 2) / cam.zoom;
		return out;
	}

	function setCurrentOffset(newX:Float, newY:Float):Void
	{
		var anim:AnimArray = (curAnim >= 0 && curAnim < anims.length) ? anims[curAnim] : null;
		if (anim == null || anim.offsets == null)
			return;

		character.offset.x = newX;
		character.offset.y = newY;
		anim.offsets[0] = Std.int(character.offset.x);
		anim.offsets[1] = Std.int(character.offset.y);
		character.addOffset(anim.anim, character.offset.x, character.offset.y);
		updateText();
		unsavedProgress = true;
	}

	function handleCtrlMouseDrag():Void
	{
		if (character == null || character.scale.x == 0 || character.scale.y == 0 || helpBg.visible)
		{
			ctrlDragging = false;
			altDragging = false;
			return;
		}

		var flip:Float = character.flipX ? -1 : 1;

		// RIGHT CLICK + DRAG = move the offset (relative, keeps the decimals so it follows the cursor)
		if (FlxG.mouse.justPressedRight)
		{
			rightAccX = rightAccY = 0;
			rightDownOnUI = isMouseOverUI();
		}
		if (FlxG.mouse.pressedRight && !rightDownOnUI && (FlxG.mouse.deltaScreenX != 0 || FlxG.mouse.deltaScreenY != 0))
		{
			var rMult:Float = FlxG.keys.pressed.CONTROL ? 0.2 : 1;
			rightAccX += FlxG.mouse.deltaScreenX / FlxG.camera.zoom * rMult;
			rightAccY += FlxG.mouse.deltaScreenY / FlxG.camera.zoom * rMult;
			var stepX:Float = rightAccX < 0 ? Math.ceil(rightAccX) : Math.floor(rightAccX);
			var stepY:Float = rightAccY < 0 ? Math.ceil(rightAccY) : Math.floor(rightAccY);
			rightAccX -= stepX;
			rightAccY -= stepY;
			if (stepX != 0 || stepY != 0)
				setCurrentOffset(character.offset.x - (stepX / character.scale.x) * flip, character.offset.y - stepY / character.scale.y);
		}

		// ALT + LEFT CLICK & DRAG = move the whole character (absolute: the grabbed point stays under the cursor)
		if (altDragging)
		{
			if (!FlxG.keys.pressed.ALT || !FlxG.mouse.pressed)
			{
				altDragging = false;
				return;
			}

			mouseToSpriteSpace(character, _mousePoint);
			var newPosX:Float = Math.round(altGrabPosX + (_mousePoint.x - altGrabWorldX));
			var newPosY:Float = Math.round(altGrabPosY + (_mousePoint.y - altGrabWorldY));
			if (newPosX != character.positionArray[0] || newPosY != character.positionArray[1])
			{
				character.positionArray[0] = newPosX;
				character.positionArray[1] = newPosY;
				positionXStepper.value = newPosX;
				positionYStepper.value = newPosY;
				updateCharacterPositions();
				unsavedProgress = true;
			}
			return;
		}

		var ctrl:Bool = FlxG.keys.pressed.CONTROL;
		if (ctrlDragging)
		{
			if (!ctrl || !FlxG.mouse.pressed)
			{
				ctrlDragging = false;
				return;
			}

			// Absolute position: the grabbed point stays under the cursor (independent of zoom/camera)
			mouseToSpriteSpace(character, _mousePoint);
			var dx:Float = (_mousePoint.x - ctrlGrabWorldX) / character.scale.x * flip;
			var dy:Float = (_mousePoint.y - ctrlGrabWorldY) / character.scale.y;
			var newX:Float = Math.round(ctrlGrabOffsetX - dx);
			var newY:Float = Math.round(ctrlGrabOffsetY - dy);
			if (newX != character.offset.x || newY != character.offset.y)
				setCurrentOffset(newX, newY);
			return;
		}

		if (!ctrl && FlxG.keys.pressed.ALT && FlxG.mouse.justPressed && !isMouseOverUI())
		{
			altDragging = true;
			draggingCharacter = false;
			mouseToSpriteSpace(character, _mousePoint);
			altGrabWorldX = _mousePoint.x;
			altGrabWorldY = _mousePoint.y;
			altGrabPosX = character.positionArray[0];
			altGrabPosY = character.positionArray[1];
			return;
		}

		// CTRL + LEFT CLICK & DRAG = move the offset (even if you miss the character)
		if (ctrl && FlxG.mouse.justPressed && !isMouseOverUI())
		{
			ctrlDragging = true;
			draggingCharacter = false;
			mouseToSpriteSpace(character, _mousePoint);
			ctrlGrabWorldX = _mousePoint.x;
			ctrlGrabWorldY = _mousePoint.y;
			ctrlGrabOffsetX = character.offset.x;
			ctrlGrabOffsetY = character.offset.y;
		}
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (xmlPickerOpen)
		{
			updateXmlPicker();
			return;
		}

		if (PsychUIInputText.focusOn != null)
		{
			ClientPrefs.toggleVolumeKeys(false);
			return;
		}
		ClientPrefs.toggleVolumeKeys(true);

		var shiftMult:Float = 1;
		var ctrlMult:Float = 1;
		var shiftMultBig:Float = 1;
		if (FlxG.keys.pressed.SHIFT || touchPad.buttonC.pressed)
		{
			shiftMult = 4;
			shiftMultBig = 10;
		}
		if (FlxG.keys.pressed.CONTROL)
			ctrlMult = 0.25;

		if (FlxG.keys.pressed.J)
			FlxG.camera.scroll.x -= elapsed * 500 * shiftMult * ctrlMult;
		if (FlxG.keys.pressed.K)
			FlxG.camera.scroll.y += elapsed * 500 * shiftMult * ctrlMult;
		if (FlxG.keys.pressed.L)
			FlxG.camera.scroll.x += elapsed * 500 * shiftMult * ctrlMult;
		if (FlxG.keys.pressed.I)
			FlxG.camera.scroll.y -= elapsed * 500 * shiftMult * ctrlMult;

		var lastZoom = FlxG.camera.zoom;
		if (FlxG.keys.justPressed.R && !FlxG.keys.pressed.CONTROL || touchPad.buttonZ.justPressed)
			FlxG.camera.zoom = 1;
		else if ((FlxG.keys.pressed.E || touchPad.buttonX.pressed) && FlxG.camera.zoom < 3)
		{
			FlxG.camera.zoom += elapsed * FlxG.camera.zoom * shiftMult * ctrlMult;
			if (FlxG.camera.zoom > 3)
				FlxG.camera.zoom = 3;
		}
		else if ((FlxG.keys.pressed.Q || touchPad.buttonY.pressed) && FlxG.camera.zoom > 0.1)
		{
			FlxG.camera.zoom -= elapsed * FlxG.camera.zoom * shiftMult * ctrlMult;
			if (FlxG.camera.zoom < 0.1)
				FlxG.camera.zoom = 0.1;
		}

		if (lastZoom != FlxG.camera.zoom)
			cameraZoomText.text = 'Zoom: ' + FlxMath.roundDecimal(FlxG.camera.zoom, 2) + 'x';

		var changedAnim:Bool = false;
		if (anims.length > 1)
		{
			if ((FlxG.keys.justPressed.W || touchPad.buttonV.justPressed) && (changedAnim = true))
				curAnim--;
			else if ((FlxG.keys.justPressed.S || touchPad.buttonD.justPressed) && (changedAnim = true))
				curAnim++;

			if (changedAnim)
			{
				undoOffsets = null;
				curAnim = FlxMath.wrap(curAnim, 0, anims.length - 1);
				character.playAnim(anims[curAnim].anim, true);
				updateText();
			}
		}

		var changedOffset = false;
		var moveKeysP = (controls.mobileC) ? [
			touchPad.buttonLeft.justPressed,
			touchPad.buttonRight.justPressed,
			touchPad.buttonUp.justPressed,
			touchPad.buttonDown.justPressed
		] : [
			FlxG.keys.justPressed.LEFT,
			FlxG.keys.justPressed.RIGHT,
			FlxG.keys.justPressed.UP,
			FlxG.keys.justPressed.DOWN
		];
		var moveKeys = (controls.mobileC) ? [
			touchPad.buttonLeft.pressed,
			touchPad.buttonRight.pressed,
			touchPad.buttonUp.pressed,
			touchPad.buttonDown.pressed
		] : [
			FlxG.keys.pressed.LEFT,
			FlxG.keys.pressed.RIGHT,
			FlxG.keys.pressed.UP,
			FlxG.keys.pressed.DOWN
		];
		if (moveKeysP.contains(true))
		{
			character.offset.x += ((moveKeysP[0] ? 1 : 0) - (moveKeysP[1] ? 1 : 0)) * shiftMultBig;
			character.offset.y += ((moveKeysP[2] ? 1 : 0) - (moveKeysP[3] ? 1 : 0)) * shiftMultBig;
			changedOffset = true;
		}

		if (moveKeys.contains(true))
		{
			holdingArrowsTime += elapsed;
			if (holdingArrowsTime > 0.6)
			{
				holdingArrowsElapsed += elapsed;
				while (holdingArrowsElapsed > (1 / 60))
				{
					character.offset.x += ((moveKeys[0] ? 1 : 0) - (moveKeys[1] ? 1 : 0)) * shiftMultBig;
					character.offset.y += ((moveKeys[2] ? 1 : 0) - (moveKeys[3] ? 1 : 0)) * shiftMultBig;
					holdingArrowsElapsed -= (1 / 60);
					changedOffset = true;
				}
			}
		}
		else
			holdingArrowsTime = 0;

		if (FlxG.keys.pressed.CONTROL)
		{
			if (FlxG.keys.justPressed.C)
			{
				copiedOffset[0] = character.offset.x;
				copiedOffset[1] = character.offset.y;
				changedOffset = true;
			}
			else if (FlxG.keys.justPressed.V)
			{
				undoOffsets = [character.offset.x, character.offset.y];
				character.offset.x = copiedOffset[0];
				character.offset.y = copiedOffset[1];
				changedOffset = true;
			}
			else if (FlxG.keys.justPressed.R)
			{
				undoOffsets = [character.offset.x, character.offset.y];
				character.offset.set(0, 0);
				changedOffset = true;
			}
			else if (FlxG.keys.justPressed.Z && undoOffsets != null)
			{
				character.offset.x = undoOffsets[0];
				character.offset.y = undoOffsets[1];
				changedOffset = true;
			}
		}
		if (touchPad.buttonA.justPressed)
		{
			undoOffsets = [character.offset.x, character.offset.y];
			character.offset.x = copiedOffset[0];
			character.offset.y = copiedOffset[1];
			changedOffset = true;
		}

		handleCtrlMouseDrag();
		if (ClientPrefs.data.dragCharacterToMove)
			handleMouseDrag();

		var anim = anims[curAnim];
		if (changedOffset && anim != null && anim.offsets != null)
		{
			anim.offsets[0] = Std.int(character.offset.x);
			anim.offsets[1] = Std.int(character.offset.y);

			character.addOffset(anim.anim, character.offset.x, character.offset.y);
			updateText();
		}

		var txt = 'ERROR: No Animation Found';
		var clr = FlxColor.RED;
		if (!character.isAnimationNull())
		{
			if (FlxG.keys.pressed.A || FlxG.keys.pressed.D)
			{
				holdingFrameTime += elapsed;
				if (holdingFrameTime > 0.5)
					holdingFrameElapsed += elapsed;
			}
			else
				holdingFrameTime = 0;

			if (FlxG.keys.justPressed.SPACE)
				character.playAnim(character.getAnimationName(), true);

			var frames:Int = -1;
			var length:Int = -1;
			if (!character.isAnimateAtlas && character.animation.curAnim != null)
			{
				frames = character.animation.curAnim.curFrame;
				length = character.animation.curAnim.numFrames;
			}
			else if (character.isAnimateAtlas && character.isCurrentAnimationAnimateAtlas() && character.atlas.anim != null)
			{
				frames = character.atlas.anim.curFrame;
				length = character.atlas.anim.length;
			}

			if (length >= 0)
			{
				if (FlxG.keys.justPressed.A || FlxG.keys.justPressed.D || holdingFrameTime > 0.5)
				{
					var isLeft = false;
					if ((holdingFrameTime > 0.5 && FlxG.keys.pressed.A) || FlxG.keys.justPressed.A)
						isLeft = true;
					character.animPaused = true;

					if (holdingFrameTime <= 0.5 || holdingFrameElapsed > 0.1)
					{
						frames = FlxMath.wrap(frames + Std.int(isLeft ? -shiftMult : shiftMult), 0, length - 1);
						if (character.isAnimateAtlas && character.isCurrentAnimationAnimateAtlas())
							character.atlas.anim.curFrame = frames;
						else
							character.animation.curAnim.curFrame = frames;
						holdingFrameElapsed -= 0.1;
					}
				}

				txt = 'Frames: ( $frames / ${length - 1} )';
				clr = FlxColor.WHITE;
			}
		}
		if (txt != frameAdvanceText.text)
			frameAdvanceText.text = txt;
		frameAdvanceText.color = clr;

		if (FlxG.keys.justPressed.F12 || touchPad.buttonS.justPressed)
			silhouettes.visible = !silhouettes.visible;

		if ((FlxG.keys.justPressed.F1 || touchPad.buttonF.justPressed) || (helpBg.visible && FlxG.keys.justPressed.ESCAPE))
		{
			if (controls.mobileC)
			{
				touchPad.forEachAlive(function(button:TouchButton)
				{
					if (button.tag != 'F')
						button.visible = !button.visible;
				});
			}
			helpBg.visible = !helpBg.visible;
			helpTexts.visible = helpBg.visible;
		}
		else if (FlxG.keys.justPressed.ESCAPE || touchPad.buttonB.justPressed)
		{
			if (!_goToPlayState)
			{
				if (!unsavedProgress)
				{
					MusicBeatState.switchState(new states.editors.MasterEditorMenu());
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
				}
				else
					openSubState(new ExitConfirmationPrompt());
			}
			else
			{
				FlxG.mouse.visible = false;
				MusicBeatState.switchState(new PlayState());
			}
			return;
		}
	}

	final assetFolder = 'week1';

	inline function loadBG()
	{
		var lastLoaded = Paths.currentLevel;
		Paths.setCurrentLevel(assetFolder);

		camEditor.bgColor = FlxColor.TRANSPARENT;
		new BackgroundStage();

		dadPosition.set(100, 100);
		bfPosition.set(770, 100);

		Paths.currentLevel = lastLoaded;
	}

	inline function updatePointerPos(?snap:Bool = true)
	{
		if (character == null || cameraFollowPointer == null)
			return;

		var offX:Float = 0;
		var offY:Float = 0;
		if (!character.isPlayer)
		{
			offX = character.getMidpoint().x + 150 + character.cameraPosition[0];
			offY = character.getMidpoint().y - 100 + character.cameraPosition[1];
		}
		else
		{
			offX = character.getMidpoint().x - 100 - character.cameraPosition[0];
			offY = character.getMidpoint().y - 100 + character.cameraPosition[1];
		}
		cameraFollowPointer.setPosition(offX, offY);

		if (snap)
		{
			FlxG.camera.scroll.x = cameraFollowPointer.getMidpoint().x - FlxG.width / 2;
			FlxG.camera.scroll.y = cameraFollowPointer.getMidpoint().y - FlxG.height / 2;
		}
	}

	inline function updateHealthBar()
	{
		healthColorStepperR.value = character.healthColorArray[0];
		healthColorStepperG.value = character.healthColorArray[1];
		healthColorStepperB.value = character.healthColorArray[2];
		healthBar.leftBar.color = healthBar.rightBar.color = FlxColor.fromRGB(character.healthColorArray[0], character.healthColorArray[1],
			character.healthColorArray[2]);
		healthIcon.changeIcon(character.healthIcon, false, character.animatedIcon == true);
		updatePresence();
	}

	function isMouseOverUI():Bool
	{
		if (xmlPickerOpen)
			return true;

		var mouseX = FlxG.mouse.screenX;
		var mouseY = FlxG.mouse.screenY;

		if (UI_box != null && UI_box.visible && UI_box.bg != null)
		{
			if (mouseX >= UI_box.x
				&& mouseX <= UI_box.x + UI_box.bg.width
				&& mouseY >= UI_box.y
				&& mouseY <= UI_box.y + UI_box.bg.height)
				return true;

			if (UI_characterbox != null && UI_characterbox.visible && UI_characterbox.bg != null)
			{
				if (mouseX >= UI_characterbox.x
					&& mouseX <= UI_characterbox.x + UI_characterbox.bg.width
					&& mouseY >= UI_characterbox.y
					&& mouseY <= UI_characterbox.y + UI_characterbox.bg.height)
					return true;
			}
		}

		if (helpBg != null && helpBg.visible)
		{
			return true;
		}

		if (controls.mobileC && touchPad != null)
		{
			var isOverButton = false;
			touchPad.forEachAlive(function(button:TouchButton)
			{
				if (button.visible && !isOverButton)
				{
					if (mouseX >= button.x && mouseX <= button.x + button.width && mouseY >= button.y && mouseY <= button.y + button.height)
						isOverButton = true;
				}
			});
			return isOverButton;
		}

		return false;
	}

	inline function updatePresence()
	{
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Character Editor", "Character: " + _char, healthIcon.getCharacter());
		#end
	}

	inline function reloadAnimList()
	{
		anims = character.animationsArray;
		if (anims.length > 0)
			character.playAnim(anims[0].anim, true);
		curAnim = 0;

		updateText();
		if (animationDropDown != null)
			reloadAnimationDropDown();
	}

	inline function updateText()
	{
		animsTxt.removeFormat(selectedFormat);

		var intendText:String = '';
		for (num => anim in anims)
		{
			if (num > 0)
				intendText += '\n';

			if (num == curAnim)
			{
				var n:Int = intendText.length;
				intendText += anim.anim + ": " + anim.offsets;
				animsTxt.addFormat(selectedFormat, n, intendText.length);
			}
			else
				intendText += anim.anim + ": " + anim.offsets;
		}
		animsTxt.text = intendText;
	}

	inline function updateCharacterPositions()
	{
		if ((character != null && !character.isPlayer) || (character == null && predictCharacterIsNotPlayer(_char)))
			character.setPosition(dadPosition.x, dadPosition.y);
		else
			character.setPosition(bfPosition.x, bfPosition.y);

		character.x += character.positionArray[0];
		character.y += character.positionArray[1];
		updatePointerPos(false);
	}

	inline function predictCharacterIsNotPlayer(name:String)
	{
		return (name != 'bf' && !name.startsWith('bf-') && !name.endsWith('-player') && !name.endsWith('-playable') && !name.endsWith('-dead'))
			|| name.endsWith('-opponent')
			|| name.startsWith('gf-')
			|| name.endsWith('-gf')
			|| name == 'gf';
	}

	function getEditorAnimateAtlasKeys(anims:Array<AnimArray>):Array<String>
	{
		var keys:Array<String> = [];
		addEditorAtlasKeys(keys, character.imageFile);

		for (anim in anims)
		{
			if (anim.assetPath == null)
				continue;

			var renderType:String = anim.renderType != null ? anim.renderType : character.renderType;
			if (Character.usesAnimateAtlas(renderType))
				addEditorAtlasKeys(keys, anim.assetPath);
		}

		return keys;
	}

	function getEditorClassicFrames(anims:Array<AnimArray>, includeBase:Bool):FlxAtlasFrames
	{
		var keys:Array<String> = [];
		if (includeBase)
			addEditorAtlasKeys(keys, character.imageFile);

		for (anim in anims)
		{
			if (anim.assetPath == null)
				continue;

			var renderType:String = anim.renderType != null ? anim.renderType : character.renderType;
			if (Character.usesClassicAtlas(renderType))
				addEditorAtlasKeys(keys, anim.assetPath);
		}

		return keys.length > 0 ? Paths.getMultiAtlas(keys) : null;
	}

	function addEditorAtlasKeys(keys:Array<String>, value:String):Void
	{
		if (value == null)
			return;

		for (key in value.split(','))
		{
			key = Character.normalizeAssetPath(key);
			if (key != null)
			{
				key = key.trim();
				if (key.length > 0 && !keys.contains(key))
					keys.push(key);
			}
		}
	}

	function addAnimation(anim:String, name:String, fps:Float, loop:Bool, indices:Array<Int>, ?animType:String, ?animRenderType:String)
	{
		var useAnimate:Bool = character.isAnimateAtlas && Character.usesAnimateAtlas(animRenderType != null ? animRenderType : character.renderType);
		character.setAnimationUsesAnimateAtlas(anim, useAnimate);
		if (!useAnimate)
		{
			if (indices != null && indices.length > 0)
				character.animation.addByIndices(anim, name, indices, "", fps, loop);
			else
				character.animation.addByPrefix(anim, name, fps, loop);
		}
		else
		{
			animType = animType != null ? animType.trim().toLowerCase() : 'framelabel';
			if (animType == 'symbol')
			{
				if (indices != null && indices.length > 0)
					character.atlas.anim.addBySymbolIndices(anim, name, indices, fps, loop);
				else
					character.atlas.anim.addBySymbol(anim, name, fps, loop);
			}
			else
			{
				if (indices != null && indices.length > 0)
					character.atlas.addByFrameLabelIndices(anim, name, indices, fps, loop);
				else
					character.atlas.addByFrameLabel(anim, name, fps, loop);
			}
		}

		if (!character.hasAnimation(anim))
			character.addOffset(anim, 0, 0);
	}

	inline function newAnim(anim:String, name:String):AnimArray
	{
		return {
			offsets: [0, 0],
			loop: false,
			fps: 24,
			anim: anim,
			indices: [],
			name: name
		};
	}

	var characterList:Array<String> = [];

	function reloadCharacterDropDown()
	{
		characterList = Mods.mergeAllTextsNamed('data/characterList.txt');
		var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getSharedPath(), 'characters/');
		for (folder in foldersToCheck)
			for (file in Paths.readDirectory(folder))
				if (file.toLowerCase().endsWith('.json'))
				{
					var charToCheck:String = file.substr(0, file.length - 5);
					if (!characterList.contains(charToCheck))
						characterList.push(charToCheck);
				}

		if (characterList.length < 1)
			characterList.push('');
		charDropDown.list = characterList;
		charDropDown.selectedLabel = _char;
	}

	function reloadAnimationDropDown()
	{
		var animList:Array<String> = [];
		for (anim in anims)
			animList.push(anim.anim);
		if (animList.length < 1)
			animList.push('NO ANIMATIONS');

		animationDropDown.list = animList;
	}

	// ---------------------------------------------------------------
	// AUTO-GENERATE ANIMATIONS FROM A SPARROW XML
	// ---------------------------------------------------------------
	static final XML_PICKER_ROWS:Int = 12;
	static final XML_PICKER_W:Int = 560;
	static final XML_PICKER_ROW_H:Int = 26;

	var xmlPickerGroup:FlxSpriteGroup;
	var xmlPickerOpen:Bool = false;
	var xmlPickerIgnoreClick:Bool = false;
	var xmlPickerEntries:Array<CharacterSheetEntry> = [];
	var xmlPickerScroll:Int = 0;
	var xmlPickerRows:Array<FlxText> = [];
	var xmlPickerHover:FlxSprite;
	var xmlPickerFooter:FlxText;
	var xmlPickerPrev:FlxText;
	var xmlPickerNext:FlxText;
	var xmlPickerX:Float = 0;
	var xmlPickerY:Float = 0;

	function makePickerRect(x:Float, y:Float, w:Float, h:Float, color:FlxColor, alpha:Float = 1):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(1, 1, color);
		spr.scale.set(w, h);
		spr.updateHitbox();
		spr.alpha = alpha;
		spr.scrollFactor.set();
		spr.active = false;
		return spr;
	}

	function makePickerText(x:Float, y:Float, w:Float, txt:String, size:Int = 16, align:flixel.text.FlxText.FlxTextAlign = LEFT):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, txt, size);
		t.setFormat(null, size, FlxColor.WHITE, align, OUTLINE_FAST, FlxColor.BLACK);
		t.borderSize = 1;
		t.scrollFactor.set();
		t.wordWrap = false;
		return t;
	}

	function addXmlPicker()
	{
		var panelH:Int = 70 + XML_PICKER_ROWS * XML_PICKER_ROW_H + 50;
		xmlPickerX = Math.round((FlxG.width - XML_PICKER_W) / 2) - 120;
		if (xmlPickerX < 10)
			xmlPickerX = 10;
		xmlPickerY = Math.round((FlxG.height - panelH) / 2);

		xmlPickerGroup = new FlxSpriteGroup();
		xmlPickerGroup.scrollFactor.set();
		xmlPickerGroup.cameras = [camHUD];

		xmlPickerGroup.add(makePickerRect(0, 0, FlxG.width, FlxG.height, FlxColor.BLACK, 0.65));
		xmlPickerGroup.add(makePickerRect(xmlPickerX - 2, xmlPickerY - 2, XML_PICKER_W + 4, panelH + 4, FlxColor.WHITE, 0.9));
		xmlPickerGroup.add(makePickerRect(xmlPickerX, xmlPickerY, XML_PICKER_W, panelH, 0xFF1E1E26));

		xmlPickerGroup.add(makePickerText(xmlPickerX + 16, xmlPickerY + 12, XML_PICKER_W - 32, 'Choose a spritesheet (images/characters)', 18));
		xmlPickerGroup.add(makePickerText(xmlPickerX + 16, xmlPickerY + 38, XML_PICKER_W - 32, 'Animations get generated from the XML and replace the current ones.', 12));

		xmlPickerHover = makePickerRect(xmlPickerX + 8, xmlPickerY + 70, XML_PICKER_W - 16, XML_PICKER_ROW_H, 0xFF3A5A9A, 0.9);
		xmlPickerHover.visible = false;
		xmlPickerGroup.add(xmlPickerHover);

		xmlPickerRows = [];
		for (i in 0...XML_PICKER_ROWS)
		{
			var row:FlxText = makePickerText(xmlPickerX + 18, xmlPickerY + 72 + i * XML_PICKER_ROW_H, XML_PICKER_W - 36, '');
			xmlPickerRows.push(row);
			xmlPickerGroup.add(row);
		}

		var footerY:Float = xmlPickerY + panelH - 34;
		xmlPickerPrev = makePickerText(xmlPickerX + 16, footerY, 80, '< Prev');
		xmlPickerNext = makePickerText(xmlPickerX + XML_PICKER_W - 96, footerY, 80, 'Next >', 16, RIGHT);
		xmlPickerFooter = makePickerText(xmlPickerX + 100, footerY + 2, XML_PICKER_W - 200, '', 12, CENTER);
		xmlPickerGroup.add(xmlPickerPrev);
		xmlPickerGroup.add(xmlPickerNext);
		xmlPickerGroup.add(xmlPickerFooter);

		xmlPickerGroup.visible = false;
		xmlPickerGroup.active = false;
		add(xmlPickerGroup);
	}

	function characterJsonExists(name:String):Bool
	{
		var path:String = Paths.getPath('characters/$name.json', TEXT, null, true);
		#if MODS_ALLOWED
		return FileSystem.exists(path);
		#else
		return Assets.exists(path);
		#end
	}

	function sheetFileExists(path:String):Bool
	{
		#if MODS_ALLOWED
		return FileSystem.exists(path);
		#else
		return Assets.exists(path);
		#end
	}

	function scanCharacterSheets():Array<CharacterSheetEntry>
	{
		var found:Map<String, CharacterSheetEntry> = new Map();
		// Same lookup order Psych uses: base assets, global mods, mods root, current mod (later ones override).
		var folders:Array<String> = Mods.directoriesWithFile(Paths.getSharedPath(), 'images/characters/');
		for (folder in folders)
			scanSheetFolder(folder, 'characters/', found, 0);

		var result:Array<CharacterSheetEntry> = [for (e in found) e];
		// Sprites without a character json first, then the already-made ones. Alphabetical inside each group.
		result.sort(function(a:CharacterSheetEntry, b:CharacterSheetEntry):Int
		{
			if (a.hasJson != b.hasJson)
				return a.hasJson ? 1 : -1;
			var ak:String = a.key.toLowerCase();
			var bk:String = b.key.toLowerCase();
			return ak < bk ? -1 : (ak > bk ? 1 : 0);
		});
		return result;
	}

	function scanSheetFolder(folder:String, keyPrefix:String, found:Map<String, CharacterSheetEntry>, depth:Int)
	{
		for (file in Paths.readDirectory(folder))
		{
			#if sys
			if (FileSystem.isDirectory(folder + file))
			{
				if (depth < 2)
					scanSheetFolder(folder + file + '/', keyPrefix + file + '/', found, depth + 1);
				continue;
			}
			#end

			if (!file.toLowerCase().endsWith('.xml'))
				continue;

			var baseName:String = file.substr(0, file.length - 4);
			if (!sheetFileExists(folder + baseName + '.png'))
				continue;

			found.set(keyPrefix + baseName, {
				key: keyPrefix + baseName,
				xmlPath: folder + file,
				hasJson: characterJsonExists(baseName)
			});
		}
	}

	function openXmlPicker()
	{
		xmlPickerEntries = scanCharacterSheets();
		xmlPickerScroll = 0;

		// group.visible overrides every member, so show it first and let refresh hide the unused rows
		xmlPickerGroup.visible = true;
		refreshXmlPicker();
		xmlPickerOpen = true;
		xmlPickerIgnoreClick = true;
		UI_box.active = false;
		UI_characterbox.active = false;
	}

	function closeXmlPicker()
	{
		xmlPickerGroup.visible = false;
		xmlPickerOpen = false;
		UI_box.active = true;
		UI_characterbox.active = true;
	}

	function refreshXmlPicker()
	{
		var maxScroll:Int = Std.int(Math.max(0, xmlPickerEntries.length - XML_PICKER_ROWS));
		xmlPickerScroll = Std.int(FlxMath.bound(xmlPickerScroll, 0, maxScroll));

		for (i in 0...XML_PICKER_ROWS)
		{
			var row:FlxText = xmlPickerRows[i];
			var idx:Int = xmlPickerScroll + i;
			if (idx < xmlPickerEntries.length)
			{
				var e:CharacterSheetEntry = xmlPickerEntries[idx];
				var label:String = e.key;
				if (label.length > 46)
					label = '...' + label.substr(label.length - 43);
				row.text = e.hasJson ? '$label   [json exists]' : label;
				row.color = e.hasJson ? 0xFF8C8C8C : FlxColor.WHITE;
				row.visible = true;
			}
			else if (i == 0 && xmlPickerEntries.length == 0)
			{
				row.text = 'No .xml + .png pairs found in images/characters/';
				row.color = 0xFFFF8080;
				row.visible = true;
			}
			else
				row.visible = false;
		}

		if (xmlPickerEntries.length > 0)
		{
			var last:Int = Std.int(Math.min(xmlPickerScroll + XML_PICKER_ROWS, xmlPickerEntries.length));
			xmlPickerFooter.text = '${xmlPickerScroll + 1}-$last of ${xmlPickerEntries.length}   |   ESC to cancel';
		}
		else
			xmlPickerFooter.text = 'ESC to cancel';

		xmlPickerPrev.visible = xmlPickerScroll > 0;
		xmlPickerNext.visible = xmlPickerScroll < maxScroll;
	}

	function pickerHit(x:Float, y:Float, w:Float, h:Float):Bool
	{
		var mx:Float = FlxG.mouse.screenX;
		var my:Float = FlxG.mouse.screenY;
		return mx >= x && mx <= x + w && my >= y && my <= y + h;
	}

	function updateXmlPicker()
	{
		ClientPrefs.toggleVolumeKeys(false);

		if (FlxG.keys.justPressed.ESCAPE || touchPad.buttonB.justPressed)
		{
			closeXmlPicker();
			return;
		}

		var maxScroll:Int = Std.int(Math.max(0, xmlPickerEntries.length - XML_PICKER_ROWS));
		var oldScroll:Int = xmlPickerScroll;
		if (FlxG.mouse.wheel != 0)
			xmlPickerScroll -= FlxG.mouse.wheel * 3;
		if (FlxG.keys.justPressed.UP)
			xmlPickerScroll--;
		if (FlxG.keys.justPressed.DOWN)
			xmlPickerScroll++;
		if (FlxG.keys.justPressed.PAGEUP)
			xmlPickerScroll -= XML_PICKER_ROWS;
		if (FlxG.keys.justPressed.PAGEDOWN)
			xmlPickerScroll += XML_PICKER_ROWS;

		var clicked:Bool = FlxG.mouse.justPressed && !xmlPickerIgnoreClick;
		xmlPickerIgnoreClick = false;

		if (clicked)
		{
			if (xmlPickerPrev.visible && pickerHit(xmlPickerPrev.x, xmlPickerPrev.y, 80, 24))
				xmlPickerScroll -= XML_PICKER_ROWS;
			else if (xmlPickerNext.visible && pickerHit(xmlPickerNext.x, xmlPickerNext.y, 80, 24))
				xmlPickerScroll += XML_PICKER_ROWS;
		}

		xmlPickerScroll = Std.int(FlxMath.bound(xmlPickerScroll, 0, maxScroll));
		if (xmlPickerScroll != oldScroll)
			refreshXmlPicker();

		// hover + click on rows
		xmlPickerHover.visible = false;
		for (i in 0...XML_PICKER_ROWS)
		{
			var idx:Int = xmlPickerScroll + i;
			if (idx >= xmlPickerEntries.length)
				break;

			var rowY:Float = xmlPickerY + 70 + i * XML_PICKER_ROW_H;
			if (pickerHit(xmlPickerX + 8, rowY, XML_PICKER_W - 16, XML_PICKER_ROW_H))
			{
				xmlPickerHover.y = rowY;
				xmlPickerHover.visible = true;
				if (clicked)
				{
					var entry:CharacterSheetEntry = xmlPickerEntries[idx];
					closeXmlPicker();
					applyXmlEntry(entry);
					return;
				}
				break;
			}
		}
	}

	function applyXmlEntry(entry:CharacterSheetEntry)
	{
		var xmlText:String = null;
		try
		{
			#if MODS_ALLOWED
			xmlText = File.getContent(entry.xmlPath);
			#else
			xmlText = Assets.getText(entry.xmlPath);
			#end
		}
		catch (e:Dynamic)
		{
			FlxG.log.warn('Could not read ${entry.xmlPath}: $e');
		}

		var newAnims:Array<AnimArray> = (xmlText != null) ? generateAnimsFromXml(xmlText) : [];
		if (newAnims.length < 1)
		{
			FlxG.log.warn('No animations found in ${entry.xmlPath}');
			FlxG.sound.play(Paths.sound('cancelMenu'));
			return;
		}

		// Wipe the old animation data and swap in the generated ones
		character.animation.destroyAnimations();
		for (k in [for (key in character.animOffsets.keys()) key])
			character.animOffsets.remove(k);

		character.animationsArray.splice(0, character.animationsArray.length);
		for (a in newAnims)
			character.animationsArray.push(a);

		character.imageFile = entry.key;
		character.renderType = 'sparrow'; // if the compiler complains about this line, delete it
		reloadCharacterImage();
		reloadAnimList();
		reloadCharacterOptions();
		if (anims.length > 0)
			animationDropDown.selectedLabel = anims[0].anim;
		updateCharacterPositions();
		updatePointerPos();
		unsavedProgress = true;

		trace('Generated ${newAnims.length} animations from ${entry.key}.xml');
	}

	/**
	 * Reads every <SubTexture name="xxxx0000"/> of a Sparrow XML, groups the frames by prefix
	 * (name minus the 4 digit frame number) and turns each group into an animation.
	 */
	function generateAnimsFromXml(xmlText:String):Array<AnimArray>
	{
		var prefixes:Array<String> = [];
		var seen:Map<String, Bool> = new Map();

		try
		{
			var root:Xml = Xml.parse(xmlText).firstElement();
			if (root == null)
				return [];

			var frameNum:EReg = ~/[0-9]{4}$/;
			for (node in root.elementsNamed('SubTexture'))
			{
				var name:String = node.get('name');
				if (name == null)
					continue;
				var prefix:String = frameNum.match(name) ? frameNum.matchedLeft() : name;
				if (!seen.exists(prefix))
				{
					seen.set(prefix, true);
					prefixes.push(prefix);
				}
			}
		}
		catch (e:Dynamic)
		{
			FlxG.log.warn('Invalid XML: $e');
			return [];
		}

		// If a prefix is the beginning of another one ("BF NOTE LEFT" / "BF NOTE LEFT MISS"),
		// add a "0" so addByPrefix doesn't grab frames of both (the base game does the same: "BF NOTE LEFT0").
		var searchNames:Array<String> = [];
		for (p in prefixes)
		{
			var clash:Bool = false;
			for (o in prefixes)
				if (o != p && o.startsWith(p))
				{
					clash = true;
					break;
				}
			searchNames.push(clash ? p + '0' : p);
		}

		// Guess names. Higher score = more confident, and wins when two prefixes want the same name.
		var guessNames:Array<String> = [];
		var guessScores:Array<Int> = [];
		for (p in prefixes)
		{
			var g = guessAnimName(p);
			guessNames.push(g.name);
			guessScores.push(g.score);
		}

		var order:Array<Int> = [for (i in 0...prefixes.length) i];
		order.sort(function(a:Int, b:Int):Int return guessScores[a] != guessScores[b] ? guessScores[b] - guessScores[a] : a - b);

		var taken:Map<String, Bool> = new Map();
		var finalNames:Array<String> = [for (_ in prefixes) ''];
		for (i in order)
		{
			var animName:String = guessNames[i];
			if (taken.exists(animName))
			{
				// Same name already used: fall back to the raw prefix so nothing is lost
				animName = ~/[0-9]+$/.replace(prefixes[i], '').trim();
				if (animName.length < 1)
					animName = prefixes[i];
				var base:String = animName;
				var n:Int = 2;
				while (taken.exists(animName))
					animName = base + (n++);
			}
			taken.set(animName, true);
			finalNames[i] = animName;
		}

		// Sort: idle, danceLeft/Right, singLEFT/DOWN/UP/RIGHT, their variants, then the rest in XML order
		var baseOrder:Array<String> = ['idle', 'danceLeft', 'danceRight', 'singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];
		var ranks:Array<Int> = [];
		for (i in 0...prefixes.length)
		{
			var an:String = finalNames[i];
			var r:Int = baseOrder.indexOf(an);
			if (r < 0)
			{
				r = 100;
				for (bi in 0...baseOrder.length)
					if (an.startsWith(baseOrder[bi]))
					{
						r = 10 + bi;
						break;
					}
			}
			ranks.push(r);
		}
		var sorted:Array<Int> = [for (i in 0...prefixes.length) i];
		sorted.sort(function(a:Int, b:Int):Int return ranks[a] != ranks[b] ? ranks[a] - ranks[b] : a - b);

		var result:Array<AnimArray> = [];
		for (i in sorted)
		{
			var anim:AnimArray = newAnim(finalNames[i], searchNames[i]);
			anim.fps = 24;
			anim.loop = false;
			result.push(anim);
		}
		return result;
	}

	function guessAnimName(prefix:String):{name:String, score:Int}
	{
		// "singLEFT" -> "sing LEFT", so words can be told apart
		var s:String = ~/([a-z])([A-Z])/g.replace(prefix, "$1 $2").toLowerCase();

		var isMiss:Bool = s.contains('miss');
		s = ~/miss/g.replace(s, ' ');
		var isAlt:Bool = ~/(^|[^a-z])alt([^a-z]|$)/.match(s);
		var altSuffix:String = isAlt ? '-alt' : '';

		var danceReg:EReg = ~/dance[^a-z]*(left|right)/;
		if (danceReg.match(s))
			return {name: 'dance' + (danceReg.matched(1) == 'left' ? 'Left' : 'Right'), score: 2};

		var dirReg:EReg = ~/(^|[^a-z])(left|down|up|right)([^a-z]|$)/;
		if (dirReg.match(s))
		{
			var hasSingWord:Bool = ~/(sing|note)/.match(s);
			return {
				name: 'sing' + dirReg.matched(2).toUpperCase() + altSuffix + (isMiss ? 'miss' : ''),
				score: hasSingWord ? 2 : 1
			};
		}

		if (~/(^|[^a-z])(idle|dance|dancing)([^a-z]|$)/.match(s))
			return {name: 'idle' + altSuffix, score: 2};

		var fallback:String = ~/[0-9]+$/.replace(prefix, '').trim();
		return {name: fallback.length > 0 ? fallback : prefix, score: 0};
	}

	// save
	var _file:FileReference;

	function onSaveComplete(_):Void
	{
		if (_file == null)
			return;
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.notice("Successfully saved file.");
	}

	function onSaveCancel(_):Void
	{
		if (_file == null)
			return;
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
	}

	function onSaveError(_):Void
	{
		if (_file == null)
			return;
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.error("Problem saving file");
	}

	function saveCharacter()
	{
		if (_file != null)
			return;

		var json:Dynamic = {
			"animations": character.animationsArray,
			"image": character.imageFile,
			"scale": character.jsonScale,
			"sing_duration": character.singDuration,
			"healthicon": character.healthIcon,

			"position": character.positionArray,
			"camera_position": character.cameraPosition,

			"flip_x": character.originalFlipX,
			"no_antialiasing": character.noAntialiasing,
			"healthbar_colors": character.healthColorArray,
			"vocals_file": character.vocalsFile,
			"_editor_isPlayer": character.isPlayer
		};

		var data:String = PsychJsonPrinter.print(json, ['offsets', 'position', 'healthbar_colors', 'camera_position', 'indices']);

		if (data.length > 0)
		{
			#if mobile
			unsavedProgress = false;
			StorageUtil.saveContent('$_char.json', data);
			#else
			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data, '$_char.json');
			#end
		}
	}

	function onMouseEvent(e:MouseEvent):Void
	{
		if (!controls.mobileC || FlxG.stage == null || UI_box == null || UI_characterbox == null)
			return;

		switch (e.type)
		{
			case MouseEvent.MOUSE_DOWN:
				if (!isMouseOverUI())
				{
					var overChar:Bool = ClientPrefs.data.dragCharacterToMove
						&& character != null
						&& FlxG.mouse.overlaps(character, camEditor);

					if (!overChar)
					{
						var mouse = new Point(e.stageX, e.stageY);
						cameraPosition.x = FlxG.camera.scroll.x + mouse.x;
						cameraPosition.y = FlxG.camera.scroll.y + mouse.y;
						isDragging = true;
					}
				}

			case MouseEvent.MOUSE_MOVE if (isDragging):
				var mouse = new Point(e.stageX, e.stageY);
				FlxG.camera.scroll.x = cameraPosition.x - mouse.x;
				FlxG.camera.scroll.y = cameraPosition.y - mouse.y;

			case MouseEvent.MOUSE_UP:
				isDragging = false;
		}
	}

	override function destroy()
	{
		if (controls.mobileC && FlxG.stage != null)
		{
			FlxG.stage.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseEvent);
			FlxG.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseEvent);
			FlxG.stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseEvent);
		}

		isDragging = false;
		draggingCharacter = false;
		ctrlDragging = false;
		altDragging = false;
		_mousePoint.put();
		super.destroy();
	}
}

typedef CharacterSheetEntry =
{
	var key:String; // e.g. characters/bf, relative to images/ and without extension
	var xmlPath:String;
	var hasJson:Bool;
}
