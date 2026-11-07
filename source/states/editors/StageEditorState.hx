package states.editors;

import backend.StageData;
import objects.Character;
import flixel.FlxObject;
import flixel.addons.display.FlxBackdrop;
import flixel.addons.display.FlxGridOverlay;
import flixel.util.FlxDestroyUtil;
import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import psychlua.backend.ModchartSprite;
import flash.net.FileFilter;
import states.editors.content.Prompt;
import states.editors.content.PreloadListSubState;

class StageEditorState extends MusicBeatState implements PsychUIEventHandler.PsychUIEvent
{
	final minZoom = 0.1;
	final maxZoom = 2;

	var gf:Character;
	var dad:Character;
	var boyfriend:Character;
	var stageJson:StageFile;

	var camGame:FlxCamera;

	public var camHUD:FlxCamera;

	var UI_stagebox:PsychUIBox;
	var UI_box:PsychUIBox;
	var spriteList_box:PsychUIBox;
	var stageSprites:Array<StageEditorMetaSprite> = [];

	public function new(stageToLoad:String = 'stage', cachedJson:StageFile = null)
	{
		lastLoadedStage = stageToLoad;
		stageJson = cachedJson;
		super();
	}

	var lastLoadedStage:String;
	var camFollow:FlxObject = new FlxObject(0, 0, 1, 1);

	// smooth zoom state
	var zoomAnimating:Bool = false;
	var targetZoom:Float = 1;
	var zoomAnchorWX:Float = 0;
	var zoomAnchorWY:Float = 0;
	var zoomAnchorSX:Float = 0;
	var zoomAnchorSY:Float = 0;

	var helpBg:FlxSprite;
	var helpTexts:FlxSpriteGroup;
	var posTxt:FlxText;
	var outputTxt:FlxText;

	var animationEditor:StageEditorAnimationSubstate;
	var unsavedProgress:Bool = false;

	var hardcodedPreview:Bool = false;
	var originalJsonObjects:Array<Dynamic> = [];

	var selectionSprites:FlxSpriteGroup = new FlxSpriteGroup();

	override function create()
	{
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();

		camGame = initPsychCamera();
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.add(camHUD, false);

		#if DISCORD_ALLOWED
		DiscordClient.changePresence('Stage Editor', 'Stage: ' + lastLoadedStage);
		#end

		if (stageJson == null)
			stageJson = StageData.getStageFile(lastLoadedStage);
		FlxG.camera.follow(null, LOCKON, 0);

		loadJsonAssetDirectory();
		gf = new Character(0, 0, stageJson._editorMeta != null ? stageJson._editorMeta.gf : 'gf');
		gf.visible = !(stageJson.hide_girlfriend);
		gf.scrollFactor.set(0.95, 0.95);
		dad = new Character(0, 0, stageJson._editorMeta != null ? stageJson._editorMeta.dad : 'dad');
		boyfriend = new Character(0, 0, stageJson._editorMeta != null ? stageJson._editorMeta.boyfriend : 'bf', true);

		for (i in 0...4)
		{
			var spr:FlxSprite = new FlxSprite().makeGraphic(1, 1, FlxColor.LIME);
			spr.alpha = 0.8;
			selectionSprites.add(spr);
		}

		FlxG.camera.zoom = stageJson.defaultZoom;
		repositionGirlfriend();
		repositionDad();
		repositionBoyfriend();
		var point = focusOnTarget('boyfriend');
		FlxG.camera.scroll.set(point.x - FlxG.width / 2, point.y - FlxG.height / 2);

		screenUI();
		spriteCreatePopup();
		editorUI();

		add(camFollow);
		updateSpriteList();

		addHelpScreen();
		buildPngPicker();
		FlxG.mouse.visible = true;
		animationEditor = new StageEditorAnimationSubstate();

		addTouchPad('LEFT_FULL', 'CHARACTER_EDITOR');
		addTouchPadCamera();

		super.create();
	}

	function loadJsonAssetDirectory()
	{
		var directory:String = 'shared';
		var weekDir:String = stageJson.directory;
		if (weekDir != null && weekDir.length > 0 && weekDir != '')
			directory = weekDir;

		Paths.setCurrentLevel(directory);
		trace('Setting asset folder to ' + directory);
	}

	var showSelectionQuad:Bool = true;

	function addHelpScreen()
	{
		#if FLX_DEBUG
		var btn = 'F3';
		#else
		var btn = 'F2';
		#end

		var str:Array<String> = (controls.mobileC) ? [
			"X/Y - Camera Zoom In/Out",
			"G + Arrow Buttons - Move Camera",
			"Z - Reset Camera Zoom",
			"Arrow Buttons/Drag - Move Object",
			"",
			"S - Toggle HUD",
			"Hold C - Move Objects and Camera 4x faster"
		] : [
			"E/Q - Camera Zoom In/Out",
			"J/K/L/I - Move Camera",
			"R - Reset Camera Zoom",
			"Arrow Keys/Mouse & Right Click - Move Object",
			"Ctrl + Left Click & Drag - Move the selected object (even if you miss it)",
			"Ctrl + Left Click on another object - Select it (click again to cycle overlapping ones)",
			"Right Click (no drag) - Deselect everything",
			"Ctrl + Scroll Wheel - Zoom In/Out at cursor",
			"",
			'$btn - Toggle HUD',
			"F12 - Toggle Selection Rectangle",
			"Hold Shift - Move Objects and Camera 4x faster",
			"Hold Control - Move Objects pixel-by-pixel and Camera 4x slower"
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

			var helpText:FlxText = new FlxText(0, 0, 680, txt, 16);
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

	function updateSpriteList()
	{
		loadJsonAssetDirectory(); // Load directory before loading sprites!

		#if sys
		if (stageJson.objects == null || stageJson.objects.length < 1)
		{
			var luaPath:String = findStageLua(lastLoadedStage);
			if (luaPath != null && FileSystem.exists(luaPath))
			{
				var fromLua:Array<Dynamic> = loadStageLuaObjects(luaPath);
				if (fromLua.length < 1)
					fromLua = parsePlainStageLua(luaPath); // hand-written Lua, no --@editor-meta
				if (fromLua.length > 0)
				{
					stageJson.objects = fromLua;
					showOutput('Loaded ${fromLua.length} object(s) from Lua.');
				}
				else
					showOutput('Lua found but no sprites could be read from it.', true);
			}
		}
		#end

		for (spr in stageSprites)
			if (spr != null && !StageData.reservedNames.contains(spr.type))
				spr.sprite = FlxDestroyUtil.destroy(spr.sprite);

		stageSprites = [];
		hardcodedPreview = false;
		var list:Map<String, FlxSprite> = [];

		if (originalJsonObjects.length < 1 && stageJson.objects != null)
			originalJsonObjects = stageJson.objects.copy();

		var hasBgInJson:Bool = false;
		if (stageJson.objects != null)
			for (data in stageJson.objects)
				if (data != null && !StageData.reservedNames.contains(data.type))
				{
					hasBgInJson = true;
					break;
				}

		if (stageJson.objects != null && stageJson.objects.length > 0)
		{
			list = StageData.addObjectsToState(stageJson.objects, gf, dad, boyfriend, null, true);
			for (key => spr in list)
				stageSprites[spr.ID] = new StageEditorMetaSprite(stageJson.objects[spr.ID], spr);
		}

		var hasBgLoaded:Bool = false;
		for (spr in stageSprites)
			if (spr != null && !StageData.reservedNames.contains(spr.type))
			{
				hasBgLoaded = true;
				break;
			}

		var jsonCount:Int = (stageJson.objects != null ? stageJson.objects.length : 0);
		trace('Stage "$lastLoadedStage": $jsonCount object(s) in the JSON, BG loaded: $hasBgLoaded');

		if (hasBgInJson && !hasBgLoaded)
		{
			showOutput('JSON has objects but none could be loaded. Check console.', true);
		}
		else if (!hasBgInJson)
		{
			var hcData = getHardcodedObjects(lastLoadedStage);
			if (hcData.length > 0)
			{
				hardcodedPreview = true;
				stageSprites = []; 
				var tmp = StageData.addObjectsToState(hcData, null, null, null, null, true);
				for (key => spr in tmp)
					stageSprites[spr.ID] = new StageEditorMetaSprite(hcData[spr.ID], spr);
				showOutput('Hardcoded preview: BG visible but NOT saveable.');
			}
			else
				showOutput('No BG sprites for "$lastLoadedStage". Add some and Save to generate the Lua.', true);
		}

		stageSprites = [for (spr in stageSprites) if (spr != null) spr];

		for (character in ['gf', 'dad', 'boyfriend'])
			if (!list.exists(character))
				stageSprites.push(new StageEditorMetaSprite({type: character}, Reflect.field(this, character)));

		updateSpriteListRadio();
	}

	function hcSpr(name:String, image:String, x:Float, y:Float, scrollX:Float = 1, scrollY:Float = 1, scale:Float = 1, filters:Dynamic = null):Dynamic
	{
		if (filters == null)
			filters = HIGH_QUALITY;
		return {type: 'sprite', name: name, image: image, x: x, y: y, scale: [scale, scale], scroll: [scrollX, scrollY], alpha: 1, angle: 0,
			color: 'FFFFFF', filters: filters, flipX: false, flipY: false, antialiasing: true};
	}

	function hcAnim(name:String, image:String, x:Float, y:Float, anims:Array<Dynamic>, scrollX:Float = 1, scrollY:Float = 1, scale:Float = 1, filters:Dynamic = null):Dynamic
	{
		if (filters == null)
			filters = HIGH_QUALITY;
		return {type: 'animatedSprite', name: name, image: image, x: x, y: y, scale: [scale, scale], scroll: [scrollX, scrollY], alpha: 1, angle: 0,
			color: 'FFFFFF', filters: filters, flipX: false, flipY: false, antialiasing: true, animations: anims, firstAnimation: anims[0].anim};
	}

	function getHardcodedObjects(stageName:String):Array<Dynamic>
	{
		switch (stageName)
		{
			case 'stage':
				return [
					{type: 'sprite', name: 'stageback',     image: 'stageback',     x: -600, y: -200, scale: [1, 1], scroll: [0.9, 0.9], alpha: 1, angle: 0, color: 'FFFFFF', filters: LOW_QUALITY | HIGH_QUALITY, flipX: false, flipY: false, antialiasing: true},
					{type: 'sprite', name: 'stagefront',    image: 'stagefront',    x: -650, y: 600,  scale: [1.1, 1.1], scroll: [0.9, 0.9], alpha: 1, angle: 0, color: 'FFFFFF', filters: LOW_QUALITY | HIGH_QUALITY, flipX: false, flipY: false, antialiasing: true},
					{type: 'sprite', name: 'stage_light_L', image: 'stage_light',   x: -125, y: -100, scale: [1.1, 1.1], scroll: [0.9, 0.9], alpha: 1, angle: 0, color: 'FFFFFF', filters: HIGH_QUALITY, flipX: false, flipY: false, antialiasing: true},
					{type: 'sprite', name: 'stage_light_R', image: 'stage_light',   x: 1225, y: -100, scale: [1.1, 1.1], scroll: [0.9, 0.9], alpha: 1, angle: 0, color: 'FFFFFF', filters: HIGH_QUALITY, flipX: true,  flipY: false, antialiasing: true},
					{type: 'sprite', name: 'stagecurtains', image: 'stagecurtains', x: -500, y: -300, scale: [0.9, 0.9], scroll: [1.3, 1.3], alpha: 1, angle: 0, color: 'FFFFFF', filters: LOW_QUALITY | HIGH_QUALITY, flipX: false, flipY: false, antialiasing: true}
				];
			case 'spooky':
				// week2: images/halloween_bg(.png/.xml) and halloween_bg_low (low quality version)
				return [
					hcSpr('halloween_bg_low', 'halloween_bg_low', -200, -100, 1, 1, 1, LOW_QUALITY),
					hcAnim('halloweenBG', 'halloween_bg', -200, -100, [
						{anim: 'idle', name: 'halloweem bg0', fps: 24, loop: false, indices: []},
						{anim: 'lightning', name: 'halloweem bg lightning strike', fps: 24, loop: false, indices: []}
					])
				];
			case 'philly':
				// week3
				return [
					hcSpr('sky', 'philly/sky', -100, 0, 0.1, 0.1),
					hcSpr('city', 'philly/city', -10, 0, 0.3, 0.3, 0.85, LOW_QUALITY | HIGH_QUALITY),
					hcSpr('window', 'philly/window', -10, 0, 0.3, 0.3, 0.85, LOW_QUALITY | HIGH_QUALITY),
					hcSpr('behindTrain', 'philly/behindTrain', -40, 50),
					hcSpr('train', 'philly/train', 2000, 360, 1, 1, 1, LOW_QUALITY | HIGH_QUALITY),
					hcSpr('street', 'philly/street', -40, 50, 1, 1, 1, LOW_QUALITY | HIGH_QUALITY)
				];
			case 'limo':
				// week4
				var limoList:Array<Dynamic> = [
					hcSpr('limoSunset', 'limo/limoSunset', -120, -50, 0.1, 0.1, 1, LOW_QUALITY | HIGH_QUALITY),
					hcSpr('metalPole', 'gore/metalPole', -500, 220, 0.4, 0.4),
					hcAnim('bgLimo', 'limo/bgLimo', -150, 480, [
						{anim: 'drive', name: 'background limo pink', fps: 24, loop: true, indices: []}
					], 0.4, 0.4)
				];
				for (i in 0...5)
					limoList.push(hcAnim('limoDancer$i', 'limo/limoDancer', (370 * i) + 170, 80, [
						{anim: 'danceLeft', name: 'bg dancer sketch PINK', fps: 24, loop: false, indices: [for (k in 0...15) k]},
						{anim: 'danceRight', name: 'bg dancer sketch PINK', fps: 24, loop: false, indices: [for (k in 15...30) k]}
					], 0.4, 0.4));
				limoList.push(hcSpr('fastCar', 'limo/fastCarLol', -300, 160, 1, 1, 1, LOW_QUALITY | HIGH_QUALITY));
				limoList.push(hcAnim('limoDrive', 'limo/limoDrive', -120, 550, [
					{anim: 'drive', name: 'Limo stage', fps: 24, loop: true, indices: []}
				], 1, 1, 1, LOW_QUALITY | HIGH_QUALITY));
				return limoList;
			case 'mall':
				// week5
				return [
					hcSpr('bgWalls', 'christmas/bgWalls', -1000, -500, 0.2, 0.2, 0.8, LOW_QUALITY | HIGH_QUALITY),
					hcAnim('upperBop', 'christmas/upperBop', -240, -90, [
						{anim: 'idle', name: 'Upper Crowd Bob', fps: 24, loop: false, indices: []}
					], 0.33, 0.33, 0.85),
					hcSpr('bgEscalator', 'christmas/bgEscalator', -1100, -600, 0.3, 0.3, 0.9),
					hcSpr('christmasTree', 'christmas/christmasTree', 370, -250, 0.4, 0.4),
					hcAnim('bottomBop', 'christmas/bottomBop', -300, 140, [
						{anim: 'idle', name: 'Bottom Level Boppers Idle', fps: 24, loop: false, indices: []},
						{anim: 'hey', name: 'Bottom Level Boppers HEY', fps: 24, loop: false, indices: []}
					], 0.9, 0.9),
					hcSpr('fgSnow', 'christmas/fgSnow', -600, 700, 1, 1, 1, LOW_QUALITY | HIGH_QUALITY),
					hcAnim('santa', 'christmas/santa', -840, 150, [
						{anim: 'idle', name: 'santa idle in fear', fps: 24, loop: false, indices: []}
					], 1, 1, 1, LOW_QUALITY | HIGH_QUALITY)
				];
			case 'mallEvil':
				// week5 (evil)
				return [
					hcSpr('evilBG', 'christmas/evilBG', -400, -500, 0.2, 0.2, 0.8, LOW_QUALITY | HIGH_QUALITY),
					hcSpr('evilTree', 'christmas/evilTree', 300, -300, 0.2, 0.2, 1, LOW_QUALITY | HIGH_QUALITY),
					hcSpr('evilSnow', 'christmas/evilSnow', -200, 700, 1, 1, 1, LOW_QUALITY | HIGH_QUALITY)
				];
			case 'school', 'schoolEvil':
				return [
					{type: 'sprite', name: 'schoolbg', image: 'school/school', x: -600, y: 0, scale: [1, 1], scroll: [1, 1], alpha: 1, angle: 0, color: 'FFFFFF', filters: HIGH_QUALITY, flipX: false, flipY: false, antialiasing: true},
					{type: 'sprite', name: 'schoolbgEscalator', image: 'school/schoolEscalator', x: -600, y: 0, scale: [1, 1], scroll: [1, 1], alpha: 1, angle: 0, color: 'FFFFFF', filters: HIGH_QUALITY, flipX: false, flipY: false, antialiasing: true},
					{type: 'sprite', name: 'schoolEvilBG', image: 'school/schoolEvil', x: -600, y: 0, scale: [1, 1], scroll: [1, 1], alpha: 1, angle: 0, color: 'FFFFFF', filters: HIGH_QUALITY, flipX: false, flipY: false, antialiasing: true}
				];
			case 'tank':
				return [
					{type: 'sprite', name: 'bg', image: 'tank/bg', x: -500, y: -100, scale: [1, 1], scroll: [1, 1], alpha: 1, angle: 0, color: 'FFFFFF', filters: HIGH_QUALITY, flipX: false, flipY: false, antialiasing: true},
					{type: 'sprite', name: 'tank', image: 'tank/tank', x: -100, y: -100, scale: [1, 1], scroll: [1, 1], alpha: 1, angle: 0, color: 'FFFFFF', filters: HIGH_QUALITY, flipX: false, flipY: false, antialiasing: true}
				];
		}
		return [];
	}

	var spriteListRadioGroup:PsychUIRadioGroup;
	var focusRadioGroup:PsychUIRadioGroup;

	function screenUI()
	{
		var lowQualityCheckbox:PsychUICheckBox = null;
		var highQualityCheckbox:PsychUICheckBox = null;
		function visibilityFilterUpdate()
		{
			curFilters = 0;
			if (lowQualityCheckbox.checked)
				curFilters |= LOW_QUALITY;
			if (highQualityCheckbox.checked)
				curFilters |= HIGH_QUALITY;
		}

		spriteList_box = new PsychUIBox(25, 40, 250, 200, ['Sprite List']);
		spriteList_box.scrollFactor.set();
		spriteList_box.cameras = [camHUD];
		add(spriteList_box);
		addSpriteListBox();

		var bg:FlxSprite = new FlxSprite(0, FlxG.height - 60).makeGraphic(1, 1, FlxColor.BLACK);
		bg.cameras = [camHUD];
		bg.alpha = 0.4;
		bg.scale.set(FlxG.width, FlxG.height - bg.y);
		bg.updateHitbox();
		add(bg);

		var tipText:FlxText = new FlxText(0, FlxG.height - 44, 300, 'Press ${(controls.mobileC) ? 'F' : 'F1'} for Help', 20);
		tipText.alignment = CENTER;
		tipText.cameras = [camHUD];
		tipText.scrollFactor.set();
		tipText.screenCenter(X);
		tipText.active = false;
		add(tipText);

		if (!controls.mobileC)
		{
			var controlsTip:FlxText = new FlxText(0, FlxG.height - 19, 700,
				'Ctrl + Left Click: select / drag  |  Click again: next overlapping  |  Right Click: deselect', 12);
			controlsTip.alignment = CENTER;
			controlsTip.alpha = 0.8;
			controlsTip.cameras = [camHUD];
			controlsTip.scrollFactor.set();
			controlsTip.screenCenter(X);
			controlsTip.active = false;
			add(controlsTip);
		}

		var targetTxt:FlxText = new FlxText(30, FlxG.height - 52, 300, 'Camera Target', 16);
		targetTxt.alignment = CENTER;
		targetTxt.cameras = [camHUD];
		targetTxt.scrollFactor.set();
		targetTxt.active = false;
		add(targetTxt);

		focusRadioGroup = new PsychUIRadioGroup(targetTxt.x, FlxG.height - 24, ['dad', 'boyfriend', 'gf'], 10, 0, true);
		focusRadioGroup.onClick = function()
		{
			var point = focusOnTarget(focusRadioGroup.labels[focusRadioGroup.checked]);
			camFollow.setPosition(point.x, point.y);
			FlxG.camera.target = camFollow;
		}
		focusRadioGroup.radios[0].label = 'Opponent';
		focusRadioGroup.radios[1].label = 'Boyfriend';
		focusRadioGroup.radios[2].label = 'Girlfriend';

		for (radio in focusRadioGroup.radios)
			radio.text.size = 11;

		focusRadioGroup.cameras = [camHUD];
		add(focusRadioGroup);

		lowQualityCheckbox = new PsychUICheckBox(FlxG.width - 240, FlxG.height - 36, 'Can see Low Quality Sprites?', 90);
		lowQualityCheckbox.cameras = [camHUD];
		lowQualityCheckbox.onClick = visibilityFilterUpdate;
		lowQualityCheckbox.checked = false;
		add(lowQualityCheckbox);

		highQualityCheckbox = new PsychUICheckBox(FlxG.width - 120, FlxG.height - 36, 'Can see High Quality Sprites?', 90);
		highQualityCheckbox.cameras = [camHUD];
		highQualityCheckbox.onClick = visibilityFilterUpdate;
		highQualityCheckbox.checked = true;
		add(highQualityCheckbox);
		visibilityFilterUpdate();

		posTxt = new FlxText(0, 50, 500, 'X: 0\nY: 0', 24);
		posTxt.setFormat(Paths.font('vcr.ttf'), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		posTxt.borderSize = 2;
		posTxt.cameras = [camHUD];
		posTxt.screenCenter(X);
		posTxt.visible = false;
		add(posTxt);

		outputTxt = new FlxText(0, 0, 800, '', 24);
		outputTxt.alignment = CENTER;
		outputTxt.borderStyle = OUTLINE_FAST;
		outputTxt.borderSize = 1;
		outputTxt.cameras = [camHUD];
		outputTxt.screenCenter();
		outputTxt.alpha = 0;
		add(outputTxt);
	}

	function addSpriteListBox()
	{
		var tab_group = spriteList_box.getTab('Sprite List').menu;
		spriteListRadioGroup = new PsychUIRadioGroup(10, 10, [], 25, 18, false, 200);
		spriteListRadioGroup.cameras = [camHUD];
		spriteListRadioGroup.onClick = function()
		{
			trace('Selected sprite: ${spriteListRadioGroup.checkedRadio.label}');
			updateSelectedUI();
		}
		tab_group.add(spriteListRadioGroup);

		var buttonX = spriteList_box.x + spriteList_box.width - 10;
		var buttonY = spriteListRadioGroup.y - 30;
		var buttonMoveUp:PsychUIButton = new PsychUIButton(buttonX, buttonY, 'Move Up', function()
		{
			var selected:Int = spriteListRadioGroup.checked;
			if (selected < 0)
				return;

			selected = spriteListRadioGroup.labels.length - selected - 1;
			var spr = stageSprites[selected];
			if (spr == null)
				return;

			var newSel:Int = Std.int(Math.min(stageSprites.length - 1, selected + 1));
			stageSprites.remove(spr);
			stageSprites.insert(newSel, spr);

			updateSpriteListRadio();
		});
		buttonMoveUp.cameras = [camHUD];
		tab_group.add(buttonMoveUp);

		var buttonMoveDown:PsychUIButton = new PsychUIButton(buttonX, buttonY + 30, 'Move Down', function()
		{
			var selected:Int = spriteListRadioGroup.checked;
			if (selected < 0)
				return;

			selected = spriteListRadioGroup.labels.length - selected - 1;
			var spr = stageSprites[selected];
			if (spr == null)
				return;

			var newSel:Int = Std.int(Math.max(0, selected - 1));
			stageSprites.remove(spr);
			stageSprites.insert(newSel, spr);

			updateSpriteListRadio();
		});
		buttonMoveDown.cameras = [camHUD];
		tab_group.add(buttonMoveDown);

		var buttonCreate:PsychUIButton = new PsychUIButton(buttonX, buttonY + 60, 'New', function() createPopup.visible = createPopup.active = true);
		buttonCreate.cameras = [camHUD];
		buttonCreate.normalStyle.bgColor = FlxColor.GREEN;
		buttonCreate.normalStyle.textColor = FlxColor.WHITE;
		tab_group.add(buttonCreate);

		var buttonDuplicate:PsychUIButton = new PsychUIButton(buttonX, buttonY + 90, 'Duplicate', function()
		{
			var selected:Int = spriteListRadioGroup.checked;
			if (selected < 0)
				return;

			selected = spriteListRadioGroup.labels.length - selected - 1;
			var spr = stageSprites[selected];
			if (spr == null || StageData.reservedNames.contains(spr.type))
				return;

			var copiedSpr = new ModchartSprite();
			var copiedMeta:StageEditorMetaSprite = new StageEditorMetaSprite(null, copiedSpr);
			for (field in Reflect.fields(spr))
			{
				if (field == 'sprite')
					continue;

				try
				{
					var fld:Dynamic = Reflect.getProperty(spr, field);
					if (fld is Array)
					{
						var arr:Array<Dynamic> = fld;
						arr = arr.copy();
						if (arr != null)
						{
							for (k => v in arr)
							{
								var indices:Array<Int> = v.indices;
								if (indices != null)
									indices = indices.copy();

								var offs:Array<Int> = v.offsets;
								if (offs != null)
									offs = offs.copy();

								fld[k] = {
									anim: v.anim,
									name: v.name,
									fps: v.fps,
									loop: v.loop,
									indices: indices,
									offsets: offs
								}
							}
						}
						fld = arr;
					}

					Reflect.setProperty(copiedMeta, field, fld);
				}
				catch (e:Dynamic)
				{
				}
			}

			if (copiedMeta.animations != null)
			{
				for (num => anim in copiedMeta.animations)
				{
					if (anim == null || anim.anim == null)
						continue;

					if (anim.indices != null && anim.indices.length > 0)
						copiedSpr.animation.addByIndices(anim.anim, anim.name, anim.indices, '', anim.fps, anim.loop);
					else
						copiedSpr.animation.addByPrefix(anim.anim, anim.name, anim.fps, anim.loop);

					if (anim.offsets != null && anim.offsets.length > 1)
						copiedSpr.addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);

					if (copiedSpr.animation.curAnim == null || copiedMeta.firstAnimation == anim.anim)
						copiedSpr.playAnim(anim.anim, true);
				}
			}
			copiedMeta.setScale(copiedMeta.scale[0], copiedMeta.scale[1]);
			copiedMeta.setScrollFactor(copiedMeta.scroll[0], copiedMeta.scroll[1]);
			copiedMeta.name = findUnoccupiedName('${copiedMeta.name}_copy');
			insertMeta(copiedMeta, 1);
		});
		buttonDuplicate.cameras = [camHUD];
		buttonDuplicate.normalStyle.bgColor = FlxColor.BLUE;
		buttonDuplicate.normalStyle.textColor = FlxColor.WHITE;
		tab_group.add(buttonDuplicate);

		var buttonDelete:PsychUIButton = new PsychUIButton(buttonX, buttonY + 120, 'Delete', function()
		{
			var selected:Int = spriteListRadioGroup.checked;
			if (selected < 0)
				return;

			selected = spriteListRadioGroup.labels.length - selected - 1;
			var spr = stageSprites[selected];
			if (spr == null || StageData.reservedNames.contains(spr.type))
				return;

			stageSprites.remove(spr);
			spr.sprite = FlxDestroyUtil.destroy(spr.sprite);

			updateSpriteListRadio();
		});
		buttonDelete.cameras = [camHUD];
		buttonDelete.normalStyle.bgColor = FlxColor.RED;
		buttonDelete.normalStyle.textColor = FlxColor.WHITE;
		tab_group.add(buttonDelete);

		var buttonImportPng:PsychUIButton = new PsychUIButton(buttonX, buttonY + 150, 'Import PNG', openPngPicker);
		buttonImportPng.cameras = [camHUD];
		buttonImportPng.normalStyle.bgColor = FlxColor.ORANGE;
		buttonImportPng.normalStyle.textColor = FlxColor.WHITE;
		tab_group.add(buttonImportPng);
	}

	function showOutput(txt:String, isError:Bool = false)
	{
		outputTxt.color = isError ? FlxColor.RED : FlxColor.WHITE;
		outputTxt.text = txt;
		outputTime = 3;

		if (isError)
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.4);
		else
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	var createPopup:FlxSpriteGroup;

	function findUnoccupiedName(prefix = 'sprite')
	{
		var num:Int = 1;
		var name:String = 'unnamed';
		while (true)
		{
			var cantUseName:Bool = false;

			name = prefix + num;
			for (basic in stageSprites)
			{
				if (basic.name == name)
				{
					cantUseName = true;
					break;
				}
			}

			if (cantUseName)
			{
				num++;
				continue;
			}
			break;
		}
		return name;
	}

	function insertMeta(meta, insertOffset:Int = 0)
	{
		var num:Int = Std.int(Math.max(0,
			Math.min(spriteListRadioGroup.labels.length, spriteListRadioGroup.labels.length - spriteListRadioGroup.checked - 1 + insertOffset)));
		stageSprites.insert(num, meta);
		updateSpriteListRadio();
		createPopup.visible = createPopup.active = false;
		spriteListRadioGroup.checked = spriteListRadioGroup.labels.length - num - 1;
		updateSelectedUI();
		unsavedProgress = true;
	}

	// ---------------------------------------------------------------
	// PNG picker: reads mods/images (and subfolders), PNG only or PNG + XML
	// ---------------------------------------------------------------
	static inline var PNG_DIR:String = 'mods/images/';

	// Every "images" folder that exists: mods/images, mods/<mod>/images, assets/images, assets/<folder>/images
	// (subfolders are scanned recursively by scanPngFolder). The current mod comes first.
	public static function getImageRoots():Array<String>
	{
		var roots:Array<String> = [];
		#if sys
		function addRoot(r:String)
		{
			if (!roots.contains(r) && FileSystem.exists(r) && FileSystem.isDirectory(r))
				roots.push(r);
		}

		#if MODS_ALLOWED
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			addRoot('mods/' + Mods.currentModDirectory + '/images/');
		addRoot('mods/images/');
		try
		{
			if (FileSystem.exists('mods') && FileSystem.isDirectory('mods'))
				for (folder in FileSystem.readDirectory('mods'))
					if (FileSystem.isDirectory('mods/' + folder))
						addRoot('mods/' + folder + '/images/');
		}
		catch (e:Dynamic) {}
		#end

		addRoot('assets/shared/images/');
		addRoot('assets/images/');
		try
		{
			if (FileSystem.exists('assets') && FileSystem.isDirectory('assets'))
				for (folder in FileSystem.readDirectory('assets'))
					if (FileSystem.isDirectory('assets/' + folder))
						addRoot('assets/' + folder + '/images/');
		}
		catch (e:Dynamic) {}
		#end
		return roots;
	}

	// Finds "<root>/<name>.<ext>" in any images folder. Returns the full path or null.
	public static function findImageFile(name:String, ext:String = 'png'):String
	{
		#if sys
		if (name == null || name.length < 1)
			return null;
		name = name.replace('\\', '/');
		if (name.startsWith('/'))
			name = name.substr(1);
		for (root in getImageRoots())
		{
			var f:String = root + name + '.' + ext;
			if (FileSystem.exists(f))
				return f;
		}
		#end
		return null;
	}
	static inline var PNG_PICKER_W:Int = 560;
	static inline var PNG_ROWS:Int = 16;
	static inline var PNG_ROW_H:Int = 20;

	var pngPickerGroup:FlxSpriteGroup;
	var pngPickerOpen:Bool = false;
	var pngEntries:Array<PngEntry> = [];
	var pngScroll:Int = 0;
	var pngRows:Array<FlxText> = [];
	var pngHoverRect:FlxSprite;
	var pngInfoText:FlxText;
	var pngPanelX:Float = 0;
	var pngPanelY:Float = 0;
	var pngPanelH:Float = 0;

	function makePngRect(x:Float, y:Float, w:Float, h:Float, color:FlxColor, alpha:Float = 1):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(1, 1, color);
		spr.scale.set(w, h);
		spr.updateHitbox();
		spr.x = x;
		spr.y = y;
		spr.alpha = alpha;
		spr.scrollFactor.set();
		return spr;
	}

	function makePngText(x:Float, y:Float, w:Float, text:String, size:Int = 14, color:FlxColor = FlxColor.WHITE):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, text, size);
		t.color = color;
		t.scrollFactor.set();
		return t;
	}

	function scanPngFolder(folder:String, prefix:String, found:Array<PngEntry>, depth:Int, rootDir:String = null)
	{
		if (rootDir == null)
			rootDir = folder;
		#if sys
		if (depth > 8 || !FileSystem.exists(folder) || !FileSystem.isDirectory(folder))
			return;

		for (file in FileSystem.readDirectory(folder))
		{
			var full:String = folder + file;
			if (FileSystem.isDirectory(full))
			{
				scanPngFolder(full + '/', prefix + file + '/', found, depth + 1, rootDir);
				continue;
			}

			if (!file.toLowerCase().endsWith('.png'))
				continue;

			var baseName:String = file.substr(0, file.length - 4);
			found.push({name: prefix + baseName, hasXml: FileSystem.exists(folder + baseName + '.xml'), root: rootDir});
		}
		#end
	}

	function openPngPicker()
	{
		pngEntries = [];
		var seen:Map<String, Bool> = [];
		for (root in getImageRoots())
		{
			var tmp:Array<PngEntry> = [];
			scanPngFolder(root, '', tmp, 0, root);
			for (e in tmp)
				if (!seen.exists(e.name))
				{
					seen.set(e.name, true);
					pngEntries.push(e);
				}
		}
		pngEntries.sort(function(a:PngEntry, b:PngEntry):Int
		{
			var ak:String = a.name.toLowerCase();
			var bk:String = b.name.toLowerCase();
			return ak < bk ? -1 : (ak > bk ? 1 : 0);
		});
		pngScroll = 0;

		if (pngPickerGroup == null)
			buildPngPicker();

		pngInfoText.text = (pngEntries.length > 0) ? '${pngEntries.length} PNG (mods + assets, all subfolders)' : 'No PNG found in mods/ or assets/';
		refreshPngRows();
		pngPickerGroup.visible = pngPickerGroup.active = pngPickerOpen = true;
	}

	function closePngPicker()
	{
		pngPickerOpen = false;
		if (pngPickerGroup != null)
			pngPickerGroup.visible = pngPickerGroup.active = false;
	}

	function buildPngPicker()
	{
		pngPanelH = 70 + PNG_ROWS * PNG_ROW_H + 40;
		pngPanelX = Math.round((FlxG.width - PNG_PICKER_W) / 2);
		pngPanelY = Math.round((FlxG.height - pngPanelH) / 2);

		pngPickerGroup = new FlxSpriteGroup();
		pngPickerGroup.cameras = [camHUD];
		pngPickerGroup.scrollFactor.set();

		pngPickerGroup.add(makePngRect(0, 0, FlxG.width, FlxG.height, FlxColor.BLACK, 0.7));
		pngPickerGroup.add(makePngRect(pngPanelX - 2, pngPanelY - 2, PNG_PICKER_W + 4, pngPanelH + 4, FlxColor.WHITE, 0.9));
		pngPickerGroup.add(makePngRect(pngPanelX, pngPanelY, PNG_PICKER_W, pngPanelH, 0xFF1E1E26));

		pngPickerGroup.add(makePngText(pngPanelX + 16, pngPanelY + 12, PNG_PICKER_W - 32, 'Import PNG', 20));
		pngInfoText = makePngText(pngPanelX + 16, pngPanelY + 42, PNG_PICKER_W - 32, '', 12, 0xFFB0B0B0);
		pngPickerGroup.add(pngInfoText);

		pngHoverRect = makePngRect(pngPanelX + 8, pngPanelY + 70, PNG_PICKER_W - 16, PNG_ROW_H, 0xFF3A5A9A, 0.8);
		pngHoverRect.visible = false;
		pngPickerGroup.add(pngHoverRect);

		pngRows = [];
		for (i in 0...PNG_ROWS)
		{
			var row:FlxText = makePngText(pngPanelX + 18, pngPanelY + 72 + i * PNG_ROW_H, PNG_PICKER_W - 36, '', 14);
			pngRows.push(row);
			pngPickerGroup.add(row);
		}

		pngPickerGroup.add(makePngText(pngPanelX + 16, pngPanelY + 70 + PNG_ROWS * PNG_ROW_H + 10, PNG_PICKER_W - 32,
			'Click = import  |  Wheel / PageUp / PageDown = scroll  |  ESC / right click = close', 12, 0xFFE0E0E0));

		add(pngPickerGroup);
		pngPickerGroup.visible = pngPickerGroup.active = false;
	}

	function refreshPngRows()
	{
		var maxScroll:Int = Std.int(Math.max(0, pngEntries.length - PNG_ROWS));
		pngScroll = Std.int(FlxMath.bound(pngScroll, 0, maxScroll));

		for (i in 0...PNG_ROWS)
		{
			var row:FlxText = pngRows[i];
			var idx:Int = pngScroll + i;
			if (idx < pngEntries.length)
			{
				var e:PngEntry = pngEntries[idx];
				row.text = e.name + (e.hasXml ? '   [PNG + XML]' : '   [PNG]');
				row.color = e.hasXml ? 0xFF8CFF9C : FlxColor.WHITE;
			}
			else
				row.text = '';
		}
	}

	// Handles the picker input (modal). Returns true if the picker is open.
	function updatePngPicker():Bool
	{
		if (!pngPickerOpen)
			return false;

		if (FlxG.keys.justPressed.ESCAPE || FlxG.mouse.justPressedRight)
		{
			closePngPicker();
			return true;
		}

		if (FlxG.mouse.wheel != 0)
		{
			pngScroll -= FlxG.mouse.wheel * 3;
			refreshPngRows();
		}
		if (FlxG.keys.justPressed.PAGEUP)
		{
			pngScroll -= PNG_ROWS;
			refreshPngRows();
		}
		if (FlxG.keys.justPressed.PAGEDOWN)
		{
			pngScroll += PNG_ROWS;
			refreshPngRows();
		}

		FlxG.mouse.getScreenPosition(camHUD, _mousePoint);
		var mx:Float = _mousePoint.x;
		var my:Float = _mousePoint.y;

		var listX:Float = pngPanelX + 8;
		var listY:Float = pngPanelY + 70;
		var overList:Bool = (mx >= listX && mx < listX + PNG_PICKER_W - 16 && my >= listY && my < listY + PNG_ROWS * PNG_ROW_H);
		var hoverIdx:Int = -1;
		if (overList)
		{
			var row:Int = Std.int((my - listY) / PNG_ROW_H);
			if (pngScroll + row < pngEntries.length)
				hoverIdx = pngScroll + row;
		}

		pngHoverRect.visible = (hoverIdx >= 0);
		if (hoverIdx >= 0)
			pngHoverRect.y = listY + (hoverIdx - pngScroll) * PNG_ROW_H;

		if (FlxG.mouse.justPressed)
		{
			if (hoverIdx >= 0)
				importPngEntry(pngEntries[hoverIdx]);
			else if (mx < pngPanelX || mx > pngPanelX + PNG_PICKER_W || my < pngPanelY || my > pngPanelY + pngPanelH)
				closePngPicker();
		}
		return true;
	}

	// Reads the animations from a Sparrow XML file: one anim per prefix
	// (the SubTexture name without the trailing frame number).
	function readXmlAnimations(xmlPath:String):Array<AnimArray>
	{
		var result:Array<AnimArray> = [];
		#if sys
		try
		{
			var root:Xml = Xml.parse(sys.io.File.getContent(xmlPath)).firstElement();
			if (root == null)
				return result;

			var frameNum:EReg = ~/[0-9]+$/;
			var seen:Map<String, Bool> = new Map();
			for (sub in root.elementsNamed('SubTexture'))
			{
				var frameName:String = sub.get('name');
				if (frameName == null)
					continue;

				var prefix:String = frameNum.replace(frameName, '');
				if (prefix.length < 1)
					prefix = frameName;
				if (seen.exists(prefix))
					continue;

				seen.set(prefix, true);
				result.push({
					anim: prefix,
					name: prefix,
					fps: 24,
					loop: false,
					indices: [],
					offsets: [0, 0]
				});
			}
		}
		catch (e:Dynamic)
		{
			trace('Could not read XML "$xmlPath": $e');
		}
		#end
		return result;
	}

	function importPngEntry(entry:PngEntry)
	{
		var anims:Array<AnimArray> = entry.hasXml ? readXmlAnimations(entry.root + entry.name + '.xml') : [];
		var type:String = (anims.length > 0) ? 'animatedSprite' : 'sprite';
		var baseName:String = entry.name.substring(entry.name.lastIndexOf('/') + 1);

		var data:Dynamic = {type: type, name: findUnoccupiedName(baseName)};
		if (type == 'animatedSprite')
		{
			data.animations = anims;
			data.firstAnimation = anims[0].anim;
		}

		insertMeta(new StageEditorMetaSprite(data, new ModchartSprite()));
		closePngPicker();

		var selected = getSelected();
		if (selected == null)
			return;

		tryLoadImage(selected, entry.name);

		if (type == 'animatedSprite')
		{
			for (anim in anims)
				selected.sprite.animation.addByPrefix(anim.anim, anim.name, anim.fps, anim.loop);
			selected.sprite.animation.play(selected.firstAnimation, true);
		}

		selected.sprite.x = Math.round(FlxG.camera.scroll.x + FlxG.width / 2 - selected.sprite.width / 2);
		selected.sprite.y = Math.round(FlxG.camera.scroll.y + FlxG.height / 2 - selected.sprite.height / 2);
		posTxt.visible = true;
		posTxt.text = 'X: ${selected.sprite.x}\nY: ${selected.sprite.y}';
		updateSelectedUI();

		showOutput('Imported "${entry.name}"' + (type == 'animatedSprite' ? ' (${anims.length} animations from XML)' : ''));
	}

	function spriteCreatePopup()
	{
		createPopup = new FlxSpriteGroup();
		createPopup.cameras = [camHUD];

		var bg:FlxSprite = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		bg.alpha = 0.6;
		bg.scale.set(300, 240);
		bg.updateHitbox();
		bg.screenCenter();
		createPopup.add(bg);

		var txt:FlxText = new FlxText(0, bg.y + 10, 180, 'New Sprite', 24);
		txt.screenCenter(X);
		txt.alignment = CENTER;
		createPopup.add(txt);

		var btnY = 320;
		var btn:PsychUIButton = new PsychUIButton(0, btnY, 'No Animation', function() loadImage('sprite'));
		btn.screenCenter(X);
		createPopup.add(btn);

		btnY += 50;
		var btn:PsychUIButton = new PsychUIButton(0, btnY, 'Animated', function() loadImage('animatedSprite'));
		btn.screenCenter(X);
		createPopup.add(btn);

		btnY += 50;
		var btn:PsychUIButton = new PsychUIButton(0, btnY, 'Solid Color', function()
		{
			var meta:StageEditorMetaSprite = new StageEditorMetaSprite({type: 'square', scale: [200, 200], name: findUnoccupiedName()}, new ModchartSprite());
			meta.sprite.makeGraphic(1, 1, FlxColor.WHITE);
			meta.sprite.scale.set(200, 200);
			meta.sprite.updateHitbox();
			meta.sprite.screenCenter();
			insertMeta(meta);
		});
		btn.screenCenter(X);
		createPopup.add(btn);
		add(createPopup);
		createPopup.visible = createPopup.active = false;
	}

	function updateSpriteListRadio()
	{
		var _sel:String = (spriteListRadioGroup.checkedRadio != null ? spriteListRadioGroup.checkedRadio.label : null);
		var nameList:Array<String> = [];
		for (spr in stageSprites)
		{
			if (spr == null)
				continue;

			switch (spr.type)
			{
				case 'gf':
					nameList.push('- Girlfriend -');
				case 'boyfriend':
					nameList.push('- Boyfriend -');
				case 'dad':
					nameList.push('- Opponent -');
				default:
					nameList.push(spr.name);
			}
		}
		nameList.reverse();

		spriteListRadioGroup.labels = nameList;
		for (radio in spriteListRadioGroup.radios)
		{
			if (radio.label == _sel)
			{
				spriteListRadioGroup.checkedRadio = radio;
				break;
			}
		}

		final maxNum:Int = 19;
		spriteList_box.resize(250, Std.int(Math.min(maxNum, spriteListRadioGroup.labels.length) * 25 + 35));
	}

	function editorUI()
	{
		UI_box = new PsychUIBox(FlxG.width - 225, 10, 200, 400, ['Meta', 'Data', 'Object']);
		UI_box.cameras = [camHUD];
		UI_box.scrollFactor.set();
		add(UI_box);
		UI_box.selectedName = 'Data';

		UI_stagebox = new PsychUIBox(FlxG.width - 275, 25, 250, 100, ['Stage']);
		UI_stagebox.cameras = [camHUD];
		UI_stagebox.scrollFactor.set();
		add(UI_stagebox);
		UI_box.y += UI_stagebox.y + UI_stagebox.height;

		addDataTab();
		addObjectTab();
		addMetaTab();
		addStageTab();
	}

	var directoryDropDown:PsychUIDropDownMenu;
	var uiInputText:PsychUIInputText;
	var hideGirlfriendCheckbox:PsychUICheckBox;
	var zoomStepper:PsychUINumericStepper;
	var cameraSpeedStepper:PsychUINumericStepper;
	var camDadStepperX:PsychUINumericStepper;
	var camDadStepperY:PsychUINumericStepper;
	var camGfStepperX:PsychUINumericStepper;
	var camGfStepperY:PsychUINumericStepper;
	var camBfStepperX:PsychUINumericStepper;
	var camBfStepperY:PsychUINumericStepper;

	function addDataTab()
	{
		var tab_group = UI_box.getTab('Data').menu;

		var objX = 10;
		var objY = 20;
		tab_group.add(new FlxText(objX, objY - 18, 150, 'Compiled Assets:'));

		var folderList:Array<String> = [''];
		#if sys
		for (folder in Paths.readDirectory('assets/'))
			if (FileSystem.isDirectory('assets/$folder') && folder != 'shared' && !Mods.ignoreModFolders.contains(folder))
				folderList.push(folder);
		#end

		var saveButton:PsychUIButton = new PsychUIButton(UI_box.width - 90, UI_box.height - 50, 'Save', function()
		{
			saveData();
		});
		tab_group.add(saveButton);

		directoryDropDown = new PsychUIDropDownMenu(objX, objY, folderList, function(sel:Int, selected:String)
		{
			if (hardcodedPreview)
			{
				showOutput('Cannot change directory while in hardcoded preview.', true);
				directoryDropDown.selectedLabel = stageJson.directory;
				return;
			}
			stageJson.directory = selected;
			saveObjectsToJson();
			FlxTransitionableState.skipNextTransIn = FlxTransitionableState.skipNextTransOut = true;
			MusicBeatState.switchState(new StageEditorState(lastLoadedStage, stageJson));
		});
		directoryDropDown.selectedLabel = stageJson.directory;

		objY += 50;
		tab_group.add(new FlxText(objX, objY - 18, 100, 'UI Style:'));
		uiInputText = new PsychUIInputText(objX, objY, 100, stageJson.stageUI != null ? stageJson.stageUI : '', 8);
		uiInputText.onChange = function(old:String, cur:String) stageJson.stageUI = uiInputText.text;

		objY += 30;
		hideGirlfriendCheckbox = new PsychUICheckBox(objX, objY, 'Hide Girlfriend?', 100);
		hideGirlfriendCheckbox.onClick = function()
		{
			stageJson.hide_girlfriend = hideGirlfriendCheckbox.checked;
			gf.visible = !hideGirlfriendCheckbox.checked;
			if (focusRadioGroup.checked > -1)
			{
				var point = focusOnTarget(focusRadioGroup.labels[focusRadioGroup.checked]);
				camFollow.setPosition(point.x, point.y);
			}
		};
		hideGirlfriendCheckbox.checked = !gf.visible;

		objY += 50;
		tab_group.add(new FlxText(objX, objY - 18, 100, 'Camera Offsets:'));

		objY += 20;
		tab_group.add(new FlxText(objX, objY - 18, 100, 'Opponent:'));

		var cx:Float = 0;
		var cy:Float = 0;
		if (stageJson.camera_opponent != null && stageJson.camera_opponent.length > 1)
		{
			cx = stageJson.camera_opponent[0];
			cy = stageJson.camera_opponent[1];
		}
		camDadStepperX = new PsychUINumericStepper(objX, objY, 50, cx, -10000, 10000, 0);
		camDadStepperY = new PsychUINumericStepper(objX + 80, objY, 50, cy, -10000, 10000, 0);
		camDadStepperX.onValueChange = camDadStepperY.onValueChange = function()
		{
			if (stageJson.camera_opponent == null)
				stageJson.camera_opponent = [0, 0];
			stageJson.camera_opponent[0] = camDadStepperX.value;
			stageJson.camera_opponent[1] = camDadStepperY.value;
			_updateCamera();
		};

		objY += 40;
		var cx:Float = 0;
		var cy:Float = 0;
		if (stageJson.camera_girlfriend != null && stageJson.camera_girlfriend.length > 1)
		{
			cx = stageJson.camera_girlfriend[0];
			cy = stageJson.camera_girlfriend[1];
		}
		tab_group.add(new FlxText(objX, objY - 18, 100, 'Girlfriend:'));
		camGfStepperX = new PsychUINumericStepper(objX, objY, 50, cx, -10000, 10000, 0);
		camGfStepperY = new PsychUINumericStepper(objX + 80, objY, 50, cy, -10000, 10000, 0);
		camGfStepperX.onValueChange = camGfStepperY.onValueChange = function()
		{
			if (stageJson.camera_girlfriend == null)
				stageJson.camera_girlfriend = [0, 0];
			stageJson.camera_girlfriend[0] = camGfStepperX.value;
			stageJson.camera_girlfriend[1] = camGfStepperY.value;
			_updateCamera();
		};

		objY += 40;
		var cx:Float = 0;
		var cy:Float = 0;
		if (stageJson.camera_boyfriend != null && stageJson.camera_boyfriend.length > 1)
		{
			cx = stageJson.camera_boyfriend[0];
			cy = stageJson.camera_boyfriend[1];
		}
		tab_group.add(new FlxText(objX, objY - 18, 100, 'Boyfriend:'));
		camBfStepperX = new PsychUINumericStepper(objX, objY, 50, cx, -10000, 10000, 0);
		camBfStepperY = new PsychUINumericStepper(objX + 80, objY, 50, cy, -10000, 10000, 0);
		camBfStepperX.onValueChange = camBfStepperY.onValueChange = function()
		{
			if (stageJson.camera_boyfriend == null)
				stageJson.camera_boyfriend = [0, 0];
			stageJson.camera_boyfriend[0] = camBfStepperX.value;
			stageJson.camera_boyfriend[1] = camBfStepperY.value;
			_updateCamera();
		};

		objY += 50;
		tab_group.add(new FlxText(objX, objY - 18, 100, 'Camera Data:'));
		objY += 20;
		tab_group.add(new FlxText(objX, objY - 18, 100, 'Zoom:'));
		zoomStepper = new PsychUINumericStepper(objX, objY, 0.05, stageJson.defaultZoom, minZoom, maxZoom, 2);
		zoomStepper.onValueChange = function()
		{
			zoomAnimating = false;
			stageJson.defaultZoom = zoomStepper.value;
			FlxG.camera.zoom = stageJson.defaultZoom;
		};

		tab_group.add(new FlxText(objX + 80, objY - 18, 100, 'Speed:'));
		cameraSpeedStepper = new PsychUINumericStepper(objX + 80, objY, 0.1, stageJson.camera_speed != null ? stageJson.camera_speed : 1, 0, 10, 2);
		cameraSpeedStepper.onValueChange = function()
		{
			stageJson.camera_speed = cameraSpeedStepper.value;
			FlxG.camera.followLerp = 0.04 * stageJson.camera_speed;
		};
		FlxG.camera.followLerp = 0.04 * cameraSpeedStepper.value;

		tab_group.add(hideGirlfriendCheckbox);
		tab_group.add(camDadStepperX);
		tab_group.add(camDadStepperY);
		tab_group.add(camGfStepperX);
		tab_group.add(camGfStepperY);
		tab_group.add(camBfStepperX);
		tab_group.add(camBfStepperY);
		tab_group.add(zoomStepper);
		tab_group.add(cameraSpeedStepper);

		tab_group.add(uiInputText);
		tab_group.add(directoryDropDown);
	}

	function _updateCamera()
	{
		if (focusRadioGroup.checked > -1)
		{
			var point = focusOnTarget(focusRadioGroup.labels[focusRadioGroup.checked]);
			camFollow.setPosition(point.x, point.y);
		}
	}

	var colorInputText:PsychUIInputText;
	var nameInputText:PsychUIInputText;
	var imgTxt:FlxText;

	var scaleStepperX:PsychUINumericStepper;
	var scaleStepperY:PsychUINumericStepper;
	var scrollStepperX:PsychUINumericStepper;
	var scrollStepperY:PsychUINumericStepper;
	var angleStepper:PsychUINumericStepper;
	var alphaStepper:PsychUINumericStepper;

	var antialiasingCheckbox:PsychUICheckBox;
	var flipXCheckBox:PsychUICheckBox;
	var flipYCheckBox:PsychUICheckBox;
	var lowQualityCheckbox:PsychUICheckBox;
	var highQualityCheckbox:PsychUICheckBox;

	function getSelected(blockReserved:Bool = true)
	{
		var selected:Int = spriteListRadioGroup.checked;
		if (selected >= 0)
		{
			var spr = stageSprites[spriteListRadioGroup.labels.length - selected - 1];
			if (spr != null && (!blockReserved || !StageData.reservedNames.contains(spr.type)))
				return spr;
		}
		return null;
	}

	function addObjectTab()
	{
		var tab_group = UI_box.getTab('Object').menu;

		var objX = 10;
		var objY = 30;
		tab_group.add(new FlxText(objX, objY - 18, 150, 'Name (for Lua/HScript):'));
		nameInputText = new PsychUIInputText(objX, objY, 120, '', 8);
		nameInputText.customFilterPattern = ~/[^a-zA-Z0-9_\-]*/g;
		nameInputText.onChange = function(old:String, cur:String)
		{
			var selected = getSelected();
			if (selected != null)
			{
				var changedName:String = nameInputText.text;
				if (changedName.length < 1)
				{
					showOutput('Sprite name cannot be empty!', true);
					return;
				}

				if (StageData.reservedNames.contains(changedName))
				{
					showOutput('To avoid conflicts, this name cannot be used!', true);
					return;
				}

				for (basic in stageSprites)
				{
					if (selected != basic && basic.name == changedName)
					{
						showOutput('Name "$changedName" is already in use!', true);
						return;
					}
				}

				selected.name = changedName;
				spriteListRadioGroup.checkedRadio.label = selected.name;
				outputTime = 0;
				outputTxt.alpha = 0;
			}
		};
		tab_group.add(nameInputText);

		objY += 35;
		imgTxt = new FlxText(objX, objY - 15, 200, 'Image: ', 8);
		var imgButton:PsychUIButton = new PsychUIButton(objX, objY, 'Change Image', function()
		{
			trace('attempt to load image');
			loadImage();
		});
		tab_group.add(imgButton);
		tab_group.add(imgTxt);

		var animationsButton:PsychUIButton = new PsychUIButton(objX + 90, objY, 'Animations', function()
		{
			var selected = getSelected();
			if (selected == null)
				return;

			if (selected.type != 'animatedSprite')
			{
				showOutput('Only Animated Sprites can hold Animation data.', true);
				return;
			}

			destroySubStates = persistentUpdate = persistentDraw = false;
			animationEditor.target = selected;
			unsavedProgress = true;
			removeTouchPad();
			openSubState(animationEditor);
		});
		tab_group.add(animationsButton);

		objY += 45;
		tab_group.add(new FlxText(objX, objY - 18, 80, 'Color:'));
		colorInputText = new PsychUIInputText(objX, objY, 80, 'FFFFFF', 8);
		colorInputText.filterMode = ONLY_ALPHANUMERIC;
		colorInputText.onChange = function(old:String, cur:String)
		{
			var selected = getSelected();
			if (selected != null)
				selected.color = colorInputText.text;
		};
		tab_group.add(colorInputText);

		function updateScale()
		{
			var selected = getSelected();
			if (selected != null)
				selected.setScale(scaleStepperX.value, scaleStepperY.value);
		}

		objY += 45;
		tab_group.add(new FlxText(objX, objY - 18, 100, 'Scale (X/Y):'));
		scaleStepperX = new PsychUINumericStepper(objX, objY, 0.05, 1, 0.05, 10, 2);
		scaleStepperY = new PsychUINumericStepper(objX + 70, objY, 0.05, 1, 0.05, 10, 2);
		scaleStepperX.onValueChange = scaleStepperY.onValueChange = updateScale;
		tab_group.add(scaleStepperX);
		tab_group.add(scaleStepperY);

		function updateScroll()
		{
			var selected = getSelected();
			if (selected != null)
				selected.setScrollFactor(scrollStepperX.value, scrollStepperY.value);
		}

		objY += 40;
		tab_group.add(new FlxText(objX, objY - 18, 150, 'Scroll Factor (X/Y):'));
		scrollStepperX = new PsychUINumericStepper(objX, objY, 0.05, 1, 0, 10, 2);
		scrollStepperY = new PsychUINumericStepper(objX + 70, objY, 0.05, 1, 0, 10, 2);
		scrollStepperX.onValueChange = scrollStepperY.onValueChange = updateScroll;
		tab_group.add(scrollStepperX);
		tab_group.add(scrollStepperY);

		objY += 40;
		tab_group.add(new FlxText(objX, objY - 18, 80, 'Opacity:'));
		alphaStepper = new PsychUINumericStepper(objX, objY, 0.1, 1, 0, 1, 2, true);
		alphaStepper.onValueChange = function()
		{
			var selected = getSelected();
			if (selected != null)
				selected.alpha = alphaStepper.value;
		};
		tab_group.add(alphaStepper);

		antialiasingCheckbox = new PsychUICheckBox(objX + 90, objY, 'Anti-Aliasing', 80);
		antialiasingCheckbox.onClick = function()
		{
			var selected = getSelected();
			if (selected != null)
			{
				if (selected.type != 'square')
					selected.antialiasing = antialiasingCheckbox.checked;
				else
				{
					antialiasingCheckbox.checked = false;
					selected.antialiasing = false;
				}
			}
		};
		tab_group.add(antialiasingCheckbox);

		objY += 40;
		tab_group.add(new FlxText(objX, objY - 18, 80, 'Angle:'));
		angleStepper = new PsychUINumericStepper(objX, objY, 10, 0, 0, 360, 0);
		angleStepper.onValueChange = function()
		{
			var selected = getSelected();
			if (selected != null)
				selected.angle = angleStepper.value;
		};
		tab_group.add(angleStepper);

		function updateFlip()
		{
			var selected = getSelected();
			if (selected != null)
			{
				if (selected.type != 'square')
				{
					selected.flipX = flipXCheckBox.checked;
					selected.flipY = flipYCheckBox.checked;
				}
				else
				{
					flipXCheckBox.checked = flipYCheckBox.checked = false;
					selected.flipX = selected.flipY = false;
				}
			}
		}

		objY += 25;
		flipXCheckBox = new PsychUICheckBox(objX, objY, 'Flip X', 60);
		flipXCheckBox.onClick = updateFlip;
		flipYCheckBox = new PsychUICheckBox(objX + 90, objY, 'Flip Y', 60);
		flipYCheckBox.onClick = updateFlip;
		tab_group.add(flipXCheckBox);
		tab_group.add(flipYCheckBox);

		objY += 45;
		function recalcFilter()
		{
			var selected = getSelected();
			if (selected != null)
			{
				var filt = 0;
				if (lowQualityCheckbox.checked)
					filt |= LOW_QUALITY;
				if (highQualityCheckbox.checked)
					filt |= HIGH_QUALITY;
				selected.filters = filt;
			}
		};
		tab_group.add(new FlxText(objX + 60, objY - 18, 100, 'Visible in:'));
		lowQualityCheckbox = new PsychUICheckBox(objX, objY, 'Low Quality', 70);
		highQualityCheckbox = new PsychUICheckBox(objX + 90, objY, 'High Quality', 70);
		lowQualityCheckbox.onClick = recalcFilter;
		highQualityCheckbox.onClick = recalcFilter;
		tab_group.add(lowQualityCheckbox);
		tab_group.add(highQualityCheckbox);
	}

	var oppDropdown:PsychUIDropDownMenu;
	var gfDropdown:PsychUIDropDownMenu;
	var plDropdown:PsychUIDropDownMenu;

	function addMetaTab()
	{
		var tab_group = UI_box.getTab('Meta').menu;

		var characterList = Mods.mergeAllTextsNamed('data/characterList.txt');
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

		var objX = 10;
		var objY = 20;

		var openPreloadButton:PsychUIButton = new PsychUIButton(objX, objY, 'Preload List', function()
		{
			var lockedList:Array<String> = [];
			var currentMap:Map<String, LoadFilters> = [];
			for (spr in stageSprites)
			{
				if (spr == null || StageData.reservedNames.contains(spr.type))
					continue;

				switch (spr.type)
				{
					case 'sprite', 'animatedSprite':
						if (spr.image != null && spr.image.length > 0 && !lockedList.contains(spr.image))
							lockedList.push(spr.image);
				}
			}

			if (stageJson.preload != null)
			{
				for (field in Reflect.fields(stageJson.preload))
				{
					if (!currentMap.exists(field) && !lockedList.contains(field))
						currentMap.set(field, Reflect.field(stageJson.preload, field));
				}
			}

			destroySubStates = true;
			openSubState(new PreloadListSubState(function(newSave:Map<String, LoadFilters>)
			{
				var len:Int = 0;
				for (name in newSave.keys())
					len++;

				stageJson.preload = {};
				for (key => value in newSave)
				{
					Reflect.setField(stageJson.preload, key, value);
				}
				unsavedProgress = true;
				showOutput('Saved new Preload List with $len files/folders!');
			}, lockedList, currentMap));
		});

		function setMetaData(data:String, char:String)
		{
			if (stageJson._editorMeta == null)
				stageJson._editorMeta = {dad: 'dad', gf: 'gf', boyfriend: 'bf'};
			Reflect.setField(stageJson._editorMeta, data, char);
		}

		objY += 60;
		oppDropdown = new PsychUIDropDownMenu(objX, objY, characterList, function(sel:Int, selected:String)
		{
			if (selected == null || selected.length < 1)
				return;
			dad.changeCharacter(selected);
			setMetaData('dad', selected);
			repositionDad();
		});
		oppDropdown.selectedLabel = dad.curCharacter;

		objY += 60;
		gfDropdown = new PsychUIDropDownMenu(objX, objY, characterList, function(sel:Int, selected:String)
		{
			if (selected == null || selected.length < 1)
				return;
			gf.changeCharacter(selected);
			setMetaData('gf', selected);
			repositionGirlfriend();
		});
		gfDropdown.selectedLabel = gf.curCharacter;

		objY += 60;
		plDropdown = new PsychUIDropDownMenu(objX, objY, characterList, function(sel:Int, selected:String)
		{
			if (selected == null || selected.length < 1)
				return;
			boyfriend.changeCharacter(selected);
			setMetaData('boyfriend', selected);
			repositionBoyfriend();
		});
		plDropdown.selectedLabel = boyfriend.curCharacter;

		tab_group.add(openPreloadButton);
		tab_group.add(new FlxText(plDropdown.x, plDropdown.y - 18, 100, 'Player:'));
		tab_group.add(plDropdown);
		tab_group.add(new FlxText(gfDropdown.x, gfDropdown.y - 18, 100, 'Girlfriend:'));
		tab_group.add(gfDropdown);
		tab_group.add(new FlxText(oppDropdown.x, oppDropdown.y - 18, 100, 'Opponent:'));
		tab_group.add(oppDropdown);
	}

	var stageDropDown:PsychUIDropDownMenu;

	function addStageTab()
	{
		var tab_group = UI_stagebox.getTab('Stage').menu;
		var reloadStage:PsychUIButton = new PsychUIButton(140, 10, 'Reload', function()
		{
			#if DISCORD_ALLOWED
			DiscordClient.changePresence('Stage Editor', 'Stage: ' + lastLoadedStage);
			#end

			stageJson = StageData.getStageFile(lastLoadedStage);
			originalJsonObjects = [];
			updateSpriteList();
			updateStageDataUI();
			reloadCharacters();
			reloadStageDropDown();
		});

		var dummyStage:PsychUIButton = new PsychUIButton(140, 40, 'Load Template', function()
		{
			#if DISCORD_ALLOWED
			DiscordClient.changePresence('Stage Editor', 'New Stage');
			#end

			stageJson = StageData.dummy();
			originalJsonObjects = [];
			updateSpriteList();
			updateStageDataUI();
			reloadCharacters();
		});
		dummyStage.normalStyle.bgColor = FlxColor.RED;
		dummyStage.normalStyle.textColor = FlxColor.WHITE;

		stageDropDown = new PsychUIDropDownMenu(10, 30, [''], function(sel:Int, selected:String)
		{
			var characterPath:String = 'stages/$selected.json';
			var path:String = Paths.getPath(characterPath, TEXT, null, true);
			#if MODS_ALLOWED
			if (FileSystem.exists(path))
			#else
			if (Assets.exists(path))
			#end
			{
				stageJson = StageData.getStageFile(selected);
				lastLoadedStage = selected;
				originalJsonObjects = [];
				#if DISCORD_ALLOWED
				DiscordClient.changePresence('Stage Editor', 'Stage: ' + lastLoadedStage);
				#end
				updateSpriteList();
				updateStageDataUI();
				reloadCharacters();
				reloadStageDropDown();
			}
			else
			{
				FlxG.sound.play(Paths.sound('cancelMenu'));
				reloadStageDropDown();
			}
		});
		reloadStageDropDown();

		tab_group.add(new FlxText(stageDropDown.x, stageDropDown.y - 18, 60, 'Stage:'));
		tab_group.add(reloadStage);
		tab_group.add(dummyStage);
		tab_group.add(stageDropDown);
	}

	function updateStageDataUI()
	{
		uiInputText.text = (stageJson.stageUI != null ? stageJson.stageUI : '');
		hideGirlfriendCheckbox.checked = (stageJson.hide_girlfriend);
		gf.visible = !hideGirlfriendCheckbox.checked;
		zoomStepper.value = FlxG.camera.zoom = stageJson.defaultZoom;

		if (stageJson.camera_speed != null)
			cameraSpeedStepper.value = stageJson.camera_speed;
		else
			cameraSpeedStepper.value = 1;
		FlxG.camera.followLerp = 0.04 * cameraSpeedStepper.value;

		if (stageJson.camera_opponent != null && stageJson.camera_opponent.length > 1)
		{
			camDadStepperX.value = stageJson.camera_opponent[0];
			camDadStepperY.value = stageJson.camera_opponent[1];
		}
		else
			camDadStepperX.value = camDadStepperY.value = 0;

		if (stageJson.camera_girlfriend != null && stageJson.camera_girlfriend.length > 1)
		{
			camGfStepperX.value = stageJson.camera_girlfriend[0];
			camGfStepperY.value = stageJson.camera_girlfriend[1];
		}
		else
			camGfStepperX.value = camGfStepperY.value = 0;

		if (stageJson.camera_boyfriend != null && stageJson.camera_boyfriend.length > 1)
		{
			camBfStepperX.value = stageJson.camera_boyfriend[0];
			camBfStepperY.value = stageJson.camera_boyfriend[1];
		}
		else
			camBfStepperX.value = camBfStepperY.value = 0;

		if (focusRadioGroup.checked > -1)
		{
			var point = focusOnTarget(focusRadioGroup.labels[focusRadioGroup.checked]);
			camFollow.setPosition(point.x, point.y);
		}
	}

	function updateSelectedUI()
	{
		posTxt.visible = false;
		var selected = getSelected(false);
		if (selected == null)
			return;

		var displayX:Float = Math.round(selected.x);
		var displayY:Float = Math.round(selected.y);

		var char:Character = Std.downcast(selected.sprite, Character);
		if (char != null)
		{
			displayX -= char.positionArray[0];
			displayY -= char.positionArray[1];
		}

		posTxt.text = 'X: $displayX\nY: $displayY';
		posTxt.visible = true;

		var selected = getSelected();
		if (selected == null)
			return;

		colorInputText.text = selected.color;
		nameInputText.text = selected.name;
		imgTxt.text = 'Image: ' + selected.image;

		if (selected.type != 'square')
		{
			scaleStepperX.decimals = scaleStepperY.decimals = 2;
			scaleStepperX.max = scaleStepperY.max = 10;
			scaleStepperX.min = scaleStepperY.min = 0.05;
			scaleStepperX.step = scaleStepperY.step = 0.05;
		}
		else
		{
			scaleStepperX.decimals = scaleStepperY.decimals = 0;
			scaleStepperX.max = scaleStepperY.max = 10000;
			scaleStepperX.min = scaleStepperY.min = 50;
			scaleStepperX.step = scaleStepperY.step = 50;
		}
		scaleStepperX.value = selected.scale[0];
		scaleStepperY.value = selected.scale[1];
		scrollStepperX.value = selected.scroll[0];
		scrollStepperY.value = selected.scroll[1];
		angleStepper.value = selected.angle;
		alphaStepper.value = selected.alpha;

		antialiasingCheckbox.checked = selected.antialiasing;
		flipXCheckBox.checked = selected.flipX;
		flipYCheckBox.checked = selected.flipY;
		lowQualityCheckbox.checked = (selected.filters & LOW_QUALITY) == LOW_QUALITY;
		highQualityCheckbox.checked = (selected.filters & HIGH_QUALITY) == HIGH_QUALITY;
	}

	function reloadCharacters()
	{
		if (stageJson._editorMeta != null)
		{
			gf.changeCharacter(stageJson._editorMeta.gf);
			dad.changeCharacter(stageJson._editorMeta.dad);
			boyfriend.changeCharacter(stageJson._editorMeta.boyfriend);
		}
		repositionGirlfriend();
		repositionDad();
		repositionBoyfriend();

		focusRadioGroup.checked = -1;
		FlxG.camera.target = null;
		var point = focusOnTarget('boyfriend');
		FlxG.camera.scroll.set(point.x - FlxG.width / 2, point.y - FlxG.height / 2);
		zoomAnimating = false;
		FlxG.camera.zoom = stageJson.defaultZoom;
		oppDropdown.selectedLabel = dad.curCharacter;
		gfDropdown.selectedLabel = gf.curCharacter;
		plDropdown.selectedLabel = boyfriend.curCharacter;
	}

	function reloadStageDropDown()
	{
		var stageList:Array<String> = [];
		var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getSharedPath(), 'stages/');
		for (folder in foldersToCheck)
			for (file in Paths.readDirectory(folder))
				if (file.toLowerCase().endsWith('.json'))
				{
					var stageToCheck:String = file.substr(0, file.length - '.json'.length);
					if (!stageList.contains(stageToCheck))
						stageList.push(stageToCheck);
				}

		if (stageList.length < 1)
			stageList.push('');
		stageDropDown.list = stageList;
		stageDropDown.selectedLabel = lastLoadedStage;
		directoryDropDown.selectedLabel = stageJson.directory;
	}

	function checkUIOnObject()
	{
		if (UI_box.selectedName == 'Object')
		{
			var selected:Int = spriteListRadioGroup.checked;
			if (selected >= 0)
			{
				var spr = stageSprites[spriteListRadioGroup.labels.length - selected - 1];
				if (spr != null && StageData.reservedNames.contains(spr.type))
					UI_box.selectedName = 'Data';
			}
			else
				UI_box.selectedName = 'Data';
		}
	}

	public function UIEvent(id:String, sender:Dynamic)
	{
		switch (id)
		{
			case PsychUIRadioGroup.CLICK_EVENT, PsychUIBox.CLICK_EVENT:
				if (sender == spriteListRadioGroup || sender == UI_box)
					checkUIOnObject();

			case PsychUICheckBox.CLICK_EVENT:
				unsavedProgress = true;

			case PsychUIInputText.CHANGE_EVENT, PsychUINumericStepper.CHANGE_EVENT:
				unsavedProgress = true;
		}
	}

	override function closeSubState()
	{
		super.closeSubState();
		controls.isInSubstate = false;
		removeTouchPad();
		addTouchPad('LEFT_FULL', 'CHARACTER_EDITOR');
		addTouchPadCamera();
		persistentUpdate = true;
	}

	var outputTime:Float = 0;

	override function update(elapsed:Float)
	{
		if (updatePngPicker())
			return;

		if (createPopup.visible && (FlxG.mouse.justPressedRight || (FlxG.mouse.justPressed && !FlxG.mouse.overlaps(createPopup, camHUD))))
			createPopup.visible = createPopup.active = false;

		for (basic in stageSprites)
			basic.update(curFilters, elapsed);

		super.update(elapsed);

		outputTime = Math.max(0, outputTime - elapsed);
		outputTxt.alpha = outputTime;

		if (PsychUIInputText.focusOn != null)
			return;

		if (FlxG.keys.justPressed.ESCAPE || touchPad.buttonB.justPressed)
		{
			if (!unsavedProgress)
			{
				MusicBeatState.switchState(new states.editors.MasterEditorMenu());
				FlxG.sound.playMusic(Paths.music('freakyMenu'));
			}
			else
				openSubState(new StageEditorExitPrompt());
			return;
		}

		if (FlxG.keys.justPressed.W || touchPad.buttonV.justPressed)
		{
			spriteListRadioGroup.checked = FlxMath.wrap(spriteListRadioGroup.checked - 1, 0, spriteListRadioGroup.labels.length - 1);
			checkUIOnObject();
			updateSelectedUI();
		}
		else if (FlxG.keys.justPressed.S || touchPad.buttonD.justPressed)
		{
			spriteListRadioGroup.checked = FlxMath.wrap(spriteListRadioGroup.checked + 1, 0, spriteListRadioGroup.labels.length - 1);
			checkUIOnObject();
			updateSelectedUI();
		}

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

		if (#if FLX_DEBUG FlxG.keys.justPressed.F3 #else FlxG.keys.justPressed.F2 #end
			|| (touchPad.buttonS.justPressed && !touchPad.buttonF.justPressed))
		{
			UI_box.visible = !UI_box.visible;
			UI_box.active = !UI_box.active;

			if (controls.mobileC)
			{
				touchPad.forEachAlive(function(button:TouchButton)
				{
					if (button.tag != 'S')
						button.visible = !button.visible;
				});
			}

			var objs = [UI_stagebox, spriteListRadioGroup, spriteList_box];
			for (obj in objs)
			{
				obj.visible = UI_box.visible;
				if (!(obj is FlxText))
					obj.active = UI_box.active;
			}
			spriteListRadioGroup.updateRadioItems();
		}

		if (FlxG.keys.justPressed.F12 || (touchPad.buttonS.justPressed && !touchPad.buttonG.justPressed))
			showSelectionQuad = !showSelectionQuad;

		updateMouseObjectDrag();

		var shiftMult:Float = 1;
		var ctrlMult:Float = 1;
		if (FlxG.keys.pressed.SHIFT || touchPad.buttonC.pressed)
			shiftMult = 4;
		if (FlxG.keys.pressed.CONTROL)
			ctrlMult = 0.25;

		// CAMERA CONTROLS
		var camX:Float = 0;
		var camY:Float = 0;
		var camMove:Float = elapsed * 500 * shiftMult * ctrlMult;
		if (FlxG.keys.pressed.J || (touchPad.buttonLeft.pressed && touchPad.buttonG.pressed))
			camX -= camMove;
		if (FlxG.keys.pressed.K || (touchPad.buttonDown.pressed && touchPad.buttonG.pressed))
			camY += camMove;
		if (FlxG.keys.pressed.L || (touchPad.buttonRight.pressed && touchPad.buttonG.pressed))
			camX += camMove;
		if (FlxG.keys.pressed.I || (touchPad.buttonUp.pressed && touchPad.buttonG.pressed))
			camY -= camMove;

		// ZOOM WITH CTRL + MOUSE WHEEL (smooth, anchored to the cursor)
		// In HaxeFlixel the zoom is centered on the CENTER of the camera, so:
		// world = scroll + size/2 + (screen - size/2) / zoom
		if (FlxG.keys.pressed.CONTROL && FlxG.mouse.wheel != 0 && !isMouseOverUI())
		{
			var cam:FlxCamera = FlxG.camera;
			if (!zoomAnimating)
				targetZoom = cam.zoom;
			targetZoom = FlxMath.bound(targetZoom * Math.pow(1.15, FlxG.mouse.wheel), minZoom, maxZoom);

			zoomAnchorSX = FlxG.mouse.screenX;
			zoomAnchorSY = FlxG.mouse.screenY;
			zoomAnchorWX = cam.scroll.x + cam.width / 2 + (zoomAnchorSX - cam.width / 2) / cam.zoom;
			zoomAnchorWY = cam.scroll.y + cam.height / 2 + (zoomAnchorSY - cam.height / 2) / cam.zoom;
			zoomAnimating = true;

			if (cam.target != null)
				cam.target = null;
			if (focusRadioGroup.checked > -1)
				focusRadioGroup.checked = -1;
		}

		if (FlxG.keys.justPressed.R || FlxG.keys.pressed.E || FlxG.keys.pressed.Q || touchPad.buttonZ.justPressed || touchPad.buttonX.pressed
			|| touchPad.buttonY.pressed)
			zoomAnimating = false; // the zoom keys take priority over the animated zoom

		if (zoomAnimating)
		{
			var cam:FlxCamera = FlxG.camera;
			// exponential interpolation, independent of the framerate
			cam.zoom += (targetZoom - cam.zoom) * (1 - Math.exp(-elapsed * 14));
			if (Math.abs(targetZoom - cam.zoom) < targetZoom * 0.0005)
			{
				cam.zoom = targetZoom;
				zoomAnimating = false;
			}
			// keeps the point under the cursor fixed while the zoom changes
			cam.scroll.x = zoomAnchorWX - cam.width / 2 - (zoomAnchorSX - cam.width / 2) / cam.zoom;
			cam.scroll.y = zoomAnchorWY - cam.height / 2 - (zoomAnchorSY - cam.height / 2) / cam.zoom;
		}

		if (camX != 0 || camY != 0)
		{
			FlxG.camera.scroll.x += camX;
			FlxG.camera.scroll.y += camY;
			if (FlxG.camera.target != null)
				FlxG.camera.target = null;
			if (focusRadioGroup.checked > -1)
				focusRadioGroup.checked = -1;
		}

		if (FlxG.keys.justPressed.R || touchPad.buttonZ.justPressed && !FlxG.keys.pressed.CONTROL)
			FlxG.camera.zoom = stageJson.defaultZoom;
		else if (FlxG.keys.pressed.E || touchPad.buttonX.pressed && FlxG.camera.zoom < maxZoom)
			FlxG.camera.zoom = Math.min(maxZoom, FlxG.camera.zoom + elapsed * FlxG.camera.zoom * shiftMult * ctrlMult);
		else if (FlxG.keys.pressed.Q || touchPad.buttonY.pressed && FlxG.camera.zoom > minZoom)
			FlxG.camera.zoom = Math.max(minZoom, FlxG.camera.zoom - elapsed * FlxG.camera.zoom * shiftMult * ctrlMult);

		var shiftMult:Float = 1;
		var ctrlMult:Float = 1;
		if (FlxG.keys.pressed.SHIFT || touchPad.buttonC.pressed)
			shiftMult = 4;
		if (FlxG.keys.pressed.CONTROL)
			ctrlMult = 0.2;

		var moveX:Float = 0;
		var moveY:Float = 0;
		if (!touchPad.buttonG.pressed)
		{
			if (FlxG.keys.justPressed.LEFT || touchPad.buttonLeft.justPressed)
				moveX -= 5 * shiftMult * ctrlMult;
			if (FlxG.keys.justPressed.RIGHT || touchPad.buttonRight.justPressed)
				moveX += 5 * shiftMult * ctrlMult;
			if (FlxG.keys.justPressed.UP || touchPad.buttonUp.justPressed)
				moveY -= 5 * shiftMult * ctrlMult;
			if (FlxG.keys.justPressed.DOWN || touchPad.buttonDown.justPressed)
				moveY += 5 * shiftMult * ctrlMult;
		}

		if (FlxG.mouse.justPressedRight)
			rightAccX = rightAccY = 0;
		if (FlxG.mouse.pressedRight && (FlxG.mouse.deltaScreenX != 0 || FlxG.mouse.deltaScreenY != 0))
		{
			// screen pixels -> world pixels (divide by the zoom) and keep the decimals, so the object follows the cursor
			rightAccX += FlxG.mouse.deltaScreenX / FlxG.camera.zoom * ctrlMult;
			rightAccY += FlxG.mouse.deltaScreenY / FlxG.camera.zoom * ctrlMult;
			var stepX:Float = rightAccX < 0 ? Math.ceil(rightAccX) : Math.floor(rightAccX);
			var stepY:Float = rightAccY < 0 ? Math.ceil(rightAccY) : Math.floor(rightAccY);
			rightAccX -= stepX;
			rightAccY -= stepY;
			moveX += stepX;
			moveY += stepY;
		}

		if (moveX != 0 || moveY != 0)
		{
			var selected:Int = spriteListRadioGroup.checked;
			if (selected < 0)
				return;

			var spr = stageSprites[spriteListRadioGroup.labels.length - selected - 1];
			if (spr != null)
				moveObjectTo(spr, Math.round(spr.x + moveX), Math.round(spr.y + moveY));
			if (FlxG.mouse.pressedRight)
				_updateCamera();
		}
	}

	var rightAccX:Float = 0;
	var rightAccY:Float = 0;
	var dragSprite:StageEditorMetaSprite = null;
	var dragPosX:Float = 0;
	var dragPosY:Float = 0;
	final _mousePoint:FlxPoint = FlxPoint.get();

	function moveObjectTo(spr:StageEditorMetaSprite, newX:Float, newY:Float)
	{
		var displayX:Float, displayY:Float;
		spr.x = displayX = newX;
		spr.y = displayY = newY;
		var char:Character = Std.downcast(spr.sprite, Character);
		if (char != null)
		{
			switch (spr.type)
			{
				case 'boyfriend':
					stageJson.boyfriend[0] = displayX = spr.x - char.positionArray[0];
					stageJson.boyfriend[1] = displayY = spr.y - char.positionArray[1];
				case 'gf':
					stageJson.girlfriend[0] = displayX = spr.x - char.positionArray[0];
					stageJson.girlfriend[1] = displayY = spr.y - char.positionArray[1];
				case 'dad':
					stageJson.opponent[0] = displayX = spr.x - char.positionArray[0];
					stageJson.opponent[1] = displayY = spr.y - char.positionArray[1];
			}
		}
		posTxt.text = 'X: $displayX\nY: $displayY';
		posTxt.visible = true;
		unsavedProgress = true;
	}

	function isMouseOverUI():Bool
	{
		if (helpBg.visible || createPopup.visible || pngPickerOpen)
			return true;
		if (UI_box.visible && FlxG.mouse.overlaps(UI_box, camHUD))
			return true;
		if (UI_stagebox.visible && FlxG.mouse.overlaps(UI_stagebox, camHUD))
			return true;
		if (spriteList_box.visible && FlxG.mouse.overlaps(spriteList_box, camHUD))
			return true;
		return FlxG.mouse.getScreenPosition(camHUD, _mousePoint).y >= FlxG.height - 60;
	}

	// Hit test with: negative scale, rotation (angle) and tolerance (pad, in world pixels)
	function mouseHitsSprite(spr:FlxSprite, worldX:Float, worldY:Float, pad:Float = 0):Bool
	{
		var w:Float = Math.abs(spr.frameWidth * spr.scale.x);
		var h:Float = Math.abs(spr.frameHeight * spr.scale.y);
		var pivotX:Float = spr.x - spr.offset.x + spr.origin.x;
		var pivotY:Float = spr.y - spr.offset.y + spr.origin.y;
		var px:Float = worldX;
		var py:Float = worldY;

		if (spr.angle != 0)
		{
			var rad:Float = -spr.angle * Math.PI / 180;
			var dx:Float = worldX - pivotX;
			var dy:Float = worldY - pivotY;
			px = pivotX + dx * Math.cos(rad) - dy * Math.sin(rad);
			py = pivotY + dx * Math.sin(rad) + dy * Math.cos(rad);
		}

		var left:Float = pivotX - spr.origin.x * spr.scale.x;
		var top:Float = pivotY - spr.origin.y * spr.scale.y;
		if (spr.scale.x < 0)
			left -= w;
		if (spr.scale.y < 0)
			top -= h;
		return px >= left - pad && px <= left + w + pad && py >= top - pad && py <= top + h + pad;
	}

	// Mouse position in the "space" of a sprite with a given scrollFactor.
	// Zoom centered on the camera center: x = scroll*sf + size/2 + (screen - size/2) / zoom
	function mouseToSpriteSpace(spr:FlxSprite, out:FlxPoint):FlxPoint
	{
		var cam:FlxCamera = FlxG.camera;
		out.x = cam.scroll.x * spr.scrollFactor.x + cam.width / 2 + (FlxG.mouse.screenX - cam.width / 2) / cam.zoom;
		out.y = cam.scroll.y * spr.scrollFactor.y + cam.height / 2 + (FlxG.mouse.screenY - cam.height / 2) / cam.zoom;
		return out;
	}

	// All the objects under the mouse, sorted: first the one selected in the list,
	// then by increasing area (small ones first, so a light under the curtains can still be grabbed).
	function getObjectsAtMouse():Array<Int>
	{
		var found:Array<{index:Int, area:Float}> = [];
		var pad:Float = 6 / FlxG.camera.zoom; // ~6px screen tolerance against "click errors"
		for (i in 0...stageSprites.length)
		{
			var meta:StageEditorMetaSprite = stageSprites[i];
			if (meta == null || meta.sprite == null || !meta.isShown(curFilters))
				continue;

			var spr:FlxSprite = meta.sprite;
			mouseToSpriteSpace(spr, _mousePoint);
			if (!mouseHitsSprite(spr, _mousePoint.x, _mousePoint.y, pad))
				continue;

			found.push({index: i, area: Math.abs(spr.frameWidth * spr.scale.x) * Math.abs(spr.frameHeight * spr.scale.y)});
		}

		var selIndex:Int = getSelectedIndex();
		found.sort(function(a, b)
		{
			if (a.index == selIndex)
				return -1;
			if (b.index == selIndex)
				return 1;
			if (a.area != b.area)
				return a.area < b.area ? -1 : 1;
			return b.index - a.index; // on equal area, the one drawn in front wins
		});
		return [for (f in found) f.index];
	}

	// index in stageSprites of the object selected in the list (-1 if none)
	function getSelectedIndex():Int
	{
		var sel:Int = spriteListRadioGroup.checked;
		if (sel < 0)
			return -1;
		var idx:Int = spriteListRadioGroup.labels.length - sel - 1;
		return (idx >= 0 && idx < stageSprites.length) ? idx : -1;
	}

	function selectMeta(index:Int)
	{
		spriteListRadioGroup.checked = spriteListRadioGroup.labels.length - index - 1;
		var meta:StageEditorMetaSprite = stageSprites[index];
		if (meta != null && !StageData.reservedNames.contains(meta.type))
			UI_box.selectedName = 'Object';
		checkUIOnObject();
		updateSelectedUI();
	}

	function deselectAll()
	{
		spriteListRadioGroup.checked = -1;
		dragSprite = null;
		checkUIOnObject();
		updateSelectedUI();
	}

	// state for the right click (deselect) and for cycling through overlapping objects
	var rightDownX:Float = 0;
	var rightDownY:Float = 0;
	var rightDownOnUI:Bool = false;
	var lastPickX:Float = -9999;
	var lastPickY:Float = -9999;
	var lastPickTime:Float = 0;
	var pickCycle:Int = 0;
	var dragMoved:Bool = false;

	function updateMouseObjectDrag()
	{
		// RIGHT CLICK without dragging = deselect all (dragging with the right button still moves the object)
		if (FlxG.mouse.justPressedRight)
		{
			rightDownX = FlxG.mouse.screenX;
			rightDownY = FlxG.mouse.screenY;
			rightDownOnUI = isMouseOverUI();
		}
		if (FlxG.mouse.justReleasedRight && !rightDownOnUI)
		{
			var dist:Float = Math.abs(FlxG.mouse.screenX - rightDownX) + Math.abs(FlxG.mouse.screenY - rightDownY);
			if (dist < 4 && getSelectedIndex() >= 0)
				deselectAll();
		}

		var ctrl:Bool = FlxG.keys.pressed.CONTROL;
		if (dragSprite != null)
		{
			if (!ctrl || !FlxG.mouse.pressed)
			{
				dragSprite = null;
				return;
			}

			// Absolute position: the grabbed point stays under the cursor (independent of zoom/scrollFactor/camera)
			mouseToSpriteSpace(dragSprite.sprite, _mousePoint);
			var newX:Float = Math.round(_mousePoint.x - dragPosX);
			var newY:Float = Math.round(_mousePoint.y - dragPosY);
			if (newX != dragSprite.x || newY != dragSprite.y)
			{
				moveObjectTo(dragSprite, newX, newY);
				dragMoved = true;
			}
			return;
		}

		if (ctrl && FlxG.mouse.justPressed && !isMouseOverUI())
		{
			var candidates:Array<Int> = getObjectsAtMouse();
			var selIndex:Int = getSelectedIndex();
			var target:Int = -1;

			if (candidates.length > 0)
			{
				// same point clicked again (without dragging) -> switch to the next overlapping object
				var now:Float = haxe.Timer.stamp();
				var sameSpot:Bool = Math.abs(FlxG.mouse.screenX - lastPickX) + Math.abs(FlxG.mouse.screenY - lastPickY) < 6
					&& now - lastPickTime < 2 && !dragMoved;
				pickCycle = sameSpot ? pickCycle + 1 : 0;
				lastPickX = FlxG.mouse.screenX;
				lastPickY = FlxG.mouse.screenY;
				lastPickTime = now;
				target = candidates[pickCycle % candidates.length];
			}
			else if (selIndex >= 0)
			{
				// click on empty space: still moves the object selected in the list (relative movement)
				target = selIndex;
				pickCycle = 0;
				lastPickX = -9999;
			}

			if (target >= 0)
			{
				if (target != selIndex)
					selectMeta(target);
				dragSprite = stageSprites[target];
				dragMoved = false;
				// offset between the clicked point and the sprite position
				mouseToSpriteSpace(dragSprite.sprite, _mousePoint);
				dragPosX = _mousePoint.x - dragSprite.x;
				dragPosY = _mousePoint.y - dragSprite.y;
			}
		}
	}

	var curFilters:LoadFilters = (LOW_QUALITY) | (HIGH_QUALITY);

	override function draw()
	{
		if (persistentDraw || subState == null)
		{
			for (basic in stageSprites)
				if (basic.visible)
					basic.draw(curFilters);

			if (showSelectionQuad && spriteListRadioGroup.checkedRadio != null)
			{
				var spr = stageSprites[spriteListRadioGroup.labels.length - spriteListRadioGroup.checked - 1];
				if (spr != null)
					drawDebugOnCamera(spr.sprite);
			}
		}

		super.draw();
	}

	function focusOnTarget(target:String)
	{
		var focusPoint:FlxPoint = FlxPoint.weak(0, 0);
		switch (target)
		{
			case 'boyfriend':
				focusPoint.x += boyfriend.getMidpoint().x - boyfriend.cameraPosition[0] - 100;
				focusPoint.y += boyfriend.getMidpoint().y + boyfriend.cameraPosition[1] - 100;
				if (stageJson.camera_boyfriend != null && stageJson.camera_boyfriend.length > 1)
				{
					focusPoint.x += stageJson.camera_boyfriend[0];
					focusPoint.y += stageJson.camera_boyfriend[1];
				}
			case 'dad':
				focusPoint.x += dad.getMidpoint().x + dad.cameraPosition[0] + 150;
				focusPoint.y += dad.getMidpoint().y + dad.cameraPosition[1] - 100;
				if (stageJson.camera_opponent != null && stageJson.camera_opponent.length > 1)
				{
					focusPoint.x += stageJson.camera_opponent[0];
					focusPoint.y += stageJson.camera_opponent[1];
				}
			case 'gf':
				if (gf.visible)
				{
					focusPoint.x += gf.getMidpoint().x + gf.cameraPosition[0];
					focusPoint.y += gf.getMidpoint().y + gf.cameraPosition[1];
				}

				if (stageJson.camera_girlfriend != null && stageJson.camera_girlfriend.length > 1)
				{
					focusPoint.x += stageJson.camera_girlfriend[0];
					focusPoint.y += stageJson.camera_girlfriend[1];
				}
		}
		return focusPoint;
	}

	function repositionGirlfriend()
	{
		gf.setPosition(stageJson.girlfriend[0], stageJson.girlfriend[1]);
		gf.x += gf.positionArray[0];
		gf.y += gf.positionArray[1];
	}

	function repositionDad()
	{
		dad.setPosition(stageJson.opponent[0], stageJson.opponent[1]);
		dad.x += dad.positionArray[0];
		dad.y += dad.positionArray[1];
	}

	function repositionBoyfriend()
	{
		boyfriend.setPosition(stageJson.boyfriend[0], stageJson.boyfriend[1]);
		boyfriend.x += boyfriend.positionArray[0];
		boyfriend.y += boyfriend.positionArray[1];
	}

	public function drawDebugOnCamera(spr:FlxSprite):Void
	{
		if (spr == null || !spr.isOnScreen(FlxG.camera))
			return;

		@:privateAccess
		var lineSize:Int = Std.int(Math.max(2, Math.floor(3 / FlxG.camera.zoom)));

		var sprX:Float = spr.x - spr.offset.x;
		var sprY:Float = spr.y - spr.offset.y;
		var sprWidth:Int = Std.int(spr.frameWidth * spr.scale.x);
		var sprHeight:Int = Std.int(spr.frameHeight * spr.scale.y);
		for (num => sel in selectionSprites.members)
		{
			sel.x = sprX;
			sel.y = sprY;
			switch (num)
			{
				case 0:
					sel.setGraphicSize(sprWidth, lineSize);
				case 1:
					sel.setGraphicSize(sprWidth, lineSize);
					sel.y += sprHeight - lineSize;
				case 2:
					sel.setGraphicSize(lineSize, sprHeight);
				case 3:
					sel.setGraphicSize(lineSize, sprHeight);
					sel.x += sprWidth - lineSize;
			}
			sel.updateHitbox();
			sel.scrollFactor.set(spr.scrollFactor.x, spr.scrollFactor.y);
		}
		selectionSprites.draw();
	}

	// Current sprites as JSON objects (same data formatToJson() produces). Used for the --@objects block of the Lua.
	function collectObjects():Array<Dynamic>
	{
		var objs:Array<Dynamic> = [];
		for (basic in stageSprites)
		{
			var json:Dynamic = basic.formatToJson();
			if (json != null)
				objs.push(json);
		}
		return objs;
	}

	// Only keeps stageJson.objects up to date IN MEMORY (directory dropdown reload).
	// It is never written to the JSON on disk: the objects go in the Lua (--@editor-meta).
	function saveObjectsToJson()
	{
		stageJson.objects = hardcodedPreview ? originalJsonObjects.copy() : collectObjects();
	}


	// Loads an image straight from disk (any images folder in mods/ or assets/) when Paths.image can't find it.
	public static function loadImageFromDisk(spr:FlxSprite, name:String, animated:Bool):Bool
	{
		#if sys
		try
		{
			var png:String = findImageFile(name);
			if (png == null)
				return false;

			var key:String = 'stageeditor_disk:' + png;
			var graphic:flixel.graphics.FlxGraphic = FlxG.bitmap.get(key);
			if (graphic == null)
				graphic = FlxG.bitmap.add(openfl.display.BitmapData.fromFile(png), false, key);
			if (graphic == null)
				return false;
			graphic.persist = true;

			if (animated)
			{
				var base:String = png.substr(0, png.length - 4);
				var frames:flixel.graphics.frames.FlxAtlasFrames = null;
				if (FileSystem.exists(base + '.xml'))
					frames = flixel.graphics.frames.FlxAtlasFrames.fromSparrow(graphic, File.getContent(base + '.xml'));
				else if (FileSystem.exists(base + '.txt'))
					frames = flixel.graphics.frames.FlxAtlasFrames.fromSpriteSheetPacker(graphic, File.getContent(base + '.txt'));
				else if (FileSystem.exists(base + '.json'))
					frames = flixel.graphics.frames.FlxAtlasFrames.fromAseprite(graphic, File.getContent(base + '.json'));
				if (frames == null)
					return false;
				spr.frames = frames;
			}
			else
				spr.loadGraphic(graphic);
			return true;
		}
		catch (e:Dynamic)
		{
			trace('Could not load "$name" from disk: $e');
		}
		#end
		return false;
	}

	// Finds stages/<name>.lua in the current mod, any mod, or any assets folder.
	function findStageLua(stageName:String):String
	{
		#if sys
		var cands:Array<String> = [];
		var viaPaths:String = null;
		try
		{
			viaPaths = Paths.getPath('stages/' + stageName + '.lua', TEXT, null, true);
		}
		catch (e:Dynamic) {}
		if (viaPaths != null)
			cands.push(viaPaths);

		#if MODS_ALLOWED
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			cands.push('mods/' + Mods.currentModDirectory + '/stages/' + stageName + '.lua');
		cands.push('mods/stages/' + stageName + '.lua');
		try
		{
			if (FileSystem.exists('mods') && FileSystem.isDirectory('mods'))
				for (f in FileSystem.readDirectory('mods'))
					cands.push('mods/' + f + '/stages/' + stageName + '.lua');
		}
		catch (e:Dynamic) {}
		#end

		cands.push('assets/shared/stages/' + stageName + '.lua');
		cands.push('assets/stages/' + stageName + '.lua');
		try
		{
			if (FileSystem.exists('assets') && FileSystem.isDirectory('assets'))
				for (f in FileSystem.readDirectory('assets'))
					cands.push('assets/' + f + '/stages/' + stageName + '.lua');
		}
		catch (e:Dynamic) {}

		for (c in cands)
			if (c != null && FileSystem.exists(c))
				return c;
		#end
		return null;
	}

	// Splits the arguments of the first "fn(...)" call found in a Lua line. Returns null if the line has no such call.
	function luaCallArgs(line:String, fn:String):Array<String>
	{
		var idx:Int = line.indexOf(fn + '(');
		if (idx < 0)
			return null;
		if (idx > 0)
		{
			var prev:String = line.charAt(idx - 1);
			if (~/[A-Za-z0-9_]/.match(prev))
				return null; // part of a longer name (e.g. "xmakeLuaSprite")
		}
		var i:Int = idx + fn.length + 1;
		var args:Array<String> = [];
		var cur:StringBuf = new StringBuf();
		var quote:String = null;
		var depth:Int = 0;
		while (i < line.length)
		{
			var c:String = line.charAt(i);
			if (quote != null)
			{
				if (c == '\\' && i + 1 < line.length)
				{
					cur.add(line.charAt(i + 1));
					i += 2;
					continue;
				}
				if (c == quote)
					quote = null;
				else
					cur.add(c);
			}
			else if (c == "'" || c == '"')
				quote = c;
			else if (c == '(')
			{
				depth++;
				cur.add(c);
			}
			else if (c == ')')
			{
				if (depth == 0)
				{
					args.push(cur.toString().trim());
					return args;
				}
				depth--;
				cur.add(c);
			}
			else if (c == ',' && depth == 0)
			{
				args.push(cur.toString().trim());
				cur = new StringBuf();
			}
			else
				cur.add(c);
			i++;
		}
		return null;
	}

	function luaFloat(s:String, def:Float):Float
	{
		if (s == null)
			return def;
		var f:Float = Std.parseFloat(s);
		return Math.isNaN(f) ? def : f;
	}

	// Reads a hand-written stage Lua (no --@editor-meta): makeLuaSprite / makeAnimatedLuaSprite + setScrollFactor,
	// scaleObject, setProperty(alpha/angle/flipX/flipY/antialiasing/color), addAnimationByPrefix, addLuaSprite.
	function parsePlainStageLua(luaPath:String):Array<Dynamic>
	{
		var created:Array<Dynamic> = [];
		var byName:Map<String, Dynamic> = [];
		var added:Array<String> = [];

		#if sys
		try
		{
			for (raw in File.getContent(luaPath).split('\n'))
			{
				var line:String = raw.trim();
				if (line.startsWith('--'))
					continue;
				var cm:Int = line.indexOf('--');
				if (cm > 0)
					line = line.substr(0, cm).trim();

				var a:Array<String> = luaCallArgs(line, 'makeLuaSprite');
				var animated:Bool = false;
				if (a == null)
				{
					a = luaCallArgs(line, 'makeAnimatedLuaSprite');
					animated = (a != null);
				}
				if (a != null && a.length >= 2)
				{
					var img:String = a[1].replace('\\', '/');
					var obj:Dynamic = {
						type: animated ? 'animatedSprite' : 'sprite',
						name: a[0],
						image: img,
						x: luaFloat(a[2], 0),
						y: luaFloat(a[3], 0),
						scale: [1.0, 1.0],
						scroll: [1.0, 1.0],
						alpha: 1,
						angle: 0,
						color: 'FFFFFF',
						filters: LOW_QUALITY | HIGH_QUALITY,
						flipX: false,
						flipY: false,
						antialiasing: true
					};
					if (animated)
					{
						obj.animations = [];
						obj.firstAnimation = null;
					}
					created.push(obj);
					byName.set(a[0], obj);
					continue;
				}

				a = luaCallArgs(line, 'setScrollFactor');
				if (a != null && a.length >= 3 && byName.exists(a[0]))
				{
					byName.get(a[0]).scroll = [luaFloat(a[1], 1), luaFloat(a[2], 1)];
					continue;
				}

				a = luaCallArgs(line, 'scaleObject');
				if (a != null && a.length >= 2 && byName.exists(a[0]))
				{
					var sx:Float = luaFloat(a[1], 1);
					byName.get(a[0]).scale = [sx, luaFloat(a[2], sx)];
					continue;
				}

				a = luaCallArgs(line, 'setProperty');
				if (a != null && a.length >= 2)
				{
					var dot:Int = a[0].lastIndexOf('.');
					if (dot > 0 && byName.exists(a[0].substr(0, dot)))
					{
						var o:Dynamic = byName.get(a[0].substr(0, dot));
						var prop:String = a[0].substr(dot + 1);
						switch (prop)
						{
							case 'alpha': o.alpha = luaFloat(a[1], 1);
							case 'angle': o.angle = luaFloat(a[1], 0);
							case 'flipX': o.flipX = (a[1] == 'true');
							case 'flipY': o.flipY = (a[1] == 'true');
							case 'antialiasing': o.antialiasing = (a[1] == 'true');
							case 'x': o.x = luaFloat(a[1], o.x);
							case 'y': o.y = luaFloat(a[1], o.y);
							case 'scale.x': o.scale = [luaFloat(a[1], 1), o.scale[1]];
							case 'scale.y': o.scale = [o.scale[0], luaFloat(a[1], 1)];
						}
					}
					continue;
				}

				a = luaCallArgs(line, 'setObjectCamera');
				if (a != null)
					continue;

				a = luaCallArgs(line, 'addAnimationByPrefix');
				if (a == null)
					a = luaCallArgs(line, 'addAnimation');
				if (a != null && a.length >= 3 && byName.exists(a[0]))
				{
					var o:Dynamic = byName.get(a[0]);
					if (o.animations != null)
					{
						o.animations.push({
							anim: a[1],
							name: a[2],
							fps: Std.int(luaFloat(a[3], 24)),
							loop: (a[4] == 'true'),
							indices: [],
							offsets: [0, 0]
						});
						if (o.firstAnimation == null)
							o.firstAnimation = a[1];
					}
					continue;
				}

				a = luaCallArgs(line, 'addLuaSprite');
				if (a != null && a.length >= 1 && byName.exists(a[0]))
					added.push(a[0]);
			}
		}
		catch (e:Dynamic)
		{
			trace('Could not parse plain Lua "$luaPath": $e');
		}
		#end

		var result:Array<Dynamic> = [];
		var source:Array<String> = added.length > 0 ? added : [for (o in created) o.name];
		var used:Map<String, Bool> = [];
		for (n in source)
		{
			if (used.exists(n))
				continue;
			used.set(n, true);
			var o:Dynamic = byName.get(n);
			if (o == null)
				continue;
			if (o.type == 'animatedSprite' && (o.animations == null || o.animations.length < 1))
			{
				// no addAnimation lines: take them from the XML next to the image
				var xml:String = findImageFile(o.image, 'xml');
				if (xml != null)
				{
					var an:Array<AnimArray> = readXmlAnimations(xml);
					if (an.length > 0)
					{
						o.animations = an;
						o.firstAnimation = an[0].anim;
					}
				}
				if (o.animations == null || o.animations.length < 1)
					o.type = 'sprite';
			}
			result.push(o);
		}
		return result;
	}

	// Reads the "--@objects" line from the "--@editor-meta" block of a stage Lua.
	function loadStageLuaObjects(luaPath:String):Array<Dynamic>
	{
		#if sys
		try
		{
			var inMeta:Bool = false;
			for (line in sys.io.File.getContent(luaPath).split('\n'))
			{
				var l:String = line.trim();
				if (l == '--@editor-meta')
				{
					inMeta = true;
					continue;
				}
				if (l == '--@end-editor-meta')
					break;

				if (inMeta && l.startsWith('--@objects '))
				{
					var parsed:Dynamic = haxe.Json.parse(l.substr('--@objects '.length));
					if (Std.isOfType(parsed, Array))
						return cast parsed;

					trace('"--@objects" in "$luaPath" is not an array.');
					return [];
				}
			}
			trace('No "--@objects" line found in "$luaPath".');
		}
		catch (e:Dynamic)
		{
			trace('Could not read objects from "$luaPath": $e');
		}
		#end
		return [];
	}

	function saveData()
	{
		if (_file != null)
			return;

		var fileName:String = lastLoadedStage;
		if (hardcodedPreview)
		{
			// Hardcoded stage: it can't be overwritten, so we export a NEW stage ("<stage>2").
			fileName = lastLoadedStage + '2';
			showOutput('Hardcoded stage: exporting as NEW stage "$fileName". The .json has no objects; the sprites are in the .lua (with its --@editor-meta block). Put both in stages/ and use it as the song stage.');
		}

		// The JSON only holds the stage data: the sprites go in the Lua, so no "objects".
		var out:Dynamic = {};
		for (field in Reflect.fields(stageJson))
			if (field != 'objects')
				Reflect.setField(out, field, Reflect.field(stageJson, field));

		var data:String = haxe.Json.stringify(out, '\t');
		var lua:String = generateStageLua(fileName);

		#if mobile
		unsavedProgress = false;
		StorageUtil.saveContent('$fileName.json', data);
		StorageUtil.saveContent('$fileName.lua', lua);
		#else
		if (data.length > 0)
		{
			_pendingLua = lua;
			_pendingLuaName = '$fileName.lua';
			startSave(data, '$fileName.json');
		}
		#end
	}

	function startSave(content:String, name:String)
	{
		_file = new FileReference();
		_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
		_file.addEventListener(Event.CANCEL, onSaveCancel);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file.save(content, name);
	}

	var _pendingLua:String = null;
	var _pendingLuaName:String = null;

	// ---------------------------------------------------------------
	// Stage Lua script generation
	// ---------------------------------------------------------------
	function luaStr(s:String):String
		return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n") + "'";

	function luaNum(v:Dynamic):String
	{
		var f:Float = (v == null) ? 0 : Std.parseFloat(Std.string(v));
		if (Math.isNaN(f))
			f = 0;
		return Std.string(Math.round(f * 10000) / 10000);
	}

	// Returns the RRGGBB hex or null if the color is white/invalid (default).
	function luaColorHex(c:Dynamic):String
	{
		if (c == null)
			return null;
		var str:String = Std.string(c).trim();
		if (str.startsWith('#'))
			str = str.substr(1);
		if (str.toLowerCase().startsWith('0x'))
			str = str.substr(2);
		if (!~/^[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.match(str))
			return null;
		str = str.substr(str.length - 6).toUpperCase();
		return (str == 'FFFFFF') ? null : str;
	}

	function luaCall(fn:String, args:Array<String>):String
		return fn + '(' + args.join(', ') + ')';

	function generateStageLua(stageName:String):String
	{
		var groupOf:Map<String, String> = [
			'gf' => 'gfGroup', 'gfGroup' => 'gfGroup',
			'dad' => 'dadGroup', 'dadGroup' => 'dadGroup',
			'boyfriend' => 'boyfriendGroup', 'boyfriendGroup' => 'boyfriendGroup'
		];

		var totalChars:Int = 0;
		for (basic in stageSprites)
			if (basic.type != null && groupOf.exists(basic.type))
				totalChars++;

		var body:Array<String> = [];
		var order:Array<String> = [];
		var charsSeen:Int = 0;
		var anchor:String = null; // what the next sprite "between" the characters must follow

		for (basic in stageSprites)
		{
			var d:Dynamic = basic.formatToJson();
			if (d == null)
				continue;

			var type:String = Std.string(d.type);
			if (groupOf.exists(type))
			{
				charsSeen++;
				anchor = luaStr(groupOf.get(type));
				continue;
			}
			if (type != 'square' && type != 'sprite' && type != 'animatedSprite')
				continue;

			var name:String = (d.name != null) ? Std.string(d.name) : 'sprite' + body.length;
			var tag:String = luaStr(name);
			var x:String = luaNum(d.x);
			var y:String = luaNum(d.y);

			// Load filters (LOW_QUALITY = 1, HIGH_QUALITY = 2, STORY_MODE = 4, FREEPLAY = 8)
			var filters:Int = (d.filters != null) ? Std.int(d.filters) : 3;
			var low:Bool = (filters & 1) != 0;
			var high:Bool = (filters & 2) != 0;
			var story:Bool = (filters & 4) != 0;
			var free:Bool = (filters & 8) != 0;
			if ((!low && !high) || (story && free))
			{
				body.push('\t-- ' + name + ': skipped (its filters never show it)');
				continue;
			}

			var conds:Array<String> = [];
			if (low && !high)
				conds.push('lowQuality');
			else if (high && !low)
				conds.push('not lowQuality');
			if (story)
				conds.push('isStoryMode');
			if (free)
				conds.push('not isStoryMode');

			var lines:Array<String> = [];
			if (type == 'square')
			{
				lines.push(luaCall('makeLuaSprite', [tag, 'nil', x, y]));
				lines.push(luaCall('makeGraphic', [tag, '1', '1', "'FFFFFF'"]));
			}
			else if (type == 'animatedSprite')
				lines.push(luaCall('makeAnimatedLuaSprite', [tag, luaStr(Std.string(d.image)), x, y]));
			else
				lines.push(luaCall('makeLuaSprite', [tag, luaStr(Std.string(d.image)), x, y]));

			var scale:Array<Dynamic> = d.scale;
			if (scale != null && scale.length > 1 && (scale[0] != 1 || scale[1] != 1))
				lines.push(luaCall('scaleObject', [tag, luaNum(scale[0]), luaNum(scale[1])]));

			var scroll:Array<Dynamic> = d.scroll;
			if (scroll != null && scroll.length > 1 && (scroll[0] != 1 || scroll[1] != 1))
				lines.push(luaCall('setScrollFactor', [tag, luaNum(scroll[0]), luaNum(scroll[1])]));

			var colorHex:String = luaColorHex(d.color);
			if (colorHex != null)
				lines.push("setProperty(" + tag + " .. '.color', getColorFromHex('" + colorHex + "'))");
			if (d.alpha != null && d.alpha != 1)
				lines.push("setProperty(" + tag + " .. '.alpha', " + luaNum(d.alpha) + ")");
			if (d.angle != null && d.angle != 0)
				lines.push("setProperty(" + tag + " .. '.angle', " + luaNum(d.angle) + ")");
			if (type != 'square')
			{
				if (d.flipX == true)
					lines.push("setProperty(" + tag + " .. '.flipX', true)");
				if (d.flipY == true)
					lines.push("setProperty(" + tag + " .. '.flipY', true)");
				if (d.antialiasing == false)
					lines.push("setProperty(" + tag + " .. '.antialiasing', false)");
			}

			if (type == 'animatedSprite' && d.animations != null)
			{
				var anims:Array<Dynamic> = d.animations;
				var firstAnim:String = (d.firstAnimation != null) ? Std.string(d.firstAnimation) : null;
				for (anim in anims)
				{
					var animName:String = luaStr(Std.string(anim.anim));
					var prefix:String = luaStr(Std.string(anim.name));
					var fps:String = luaNum(anim.fps != null ? anim.fps : 24);
					var loop:String = (anim.loop == true) ? 'true' : 'false';
					var indices:Array<Dynamic> = anim.indices;

					if (indices == null || indices.length < 1)
						lines.push(luaCall('addAnimationByPrefix', [tag, animName, prefix, fps, loop]));
					else
						lines.push(luaCall('addAnimationByIndices', [tag, animName, prefix, luaStr(indices.join(',')), fps, loop]));

					var offsets:Array<Dynamic> = anim.offsets;
					if (offsets != null && offsets.length > 1 && (offsets[0] != 0 || offsets[1] != 0))
						lines.push(luaCall('addOffset', [tag, animName, luaNum(offsets[0]), luaNum(offsets[1])]));

					if (firstAnim == null)
						firstAnim = Std.string(anim.anim);
				}
				if (firstAnim != null && anims.length > 0)
					lines.push(luaCall('playAnim', [tag, luaStr(firstAnim), 'true']));
			}

			// Position relative to the characters: behind all, in front of all, or in between.
			var orderLine:String = null;
			if (charsSeen >= totalChars && charsSeen > 0)
				lines.push(luaCall('addLuaSprite', [tag, 'true']));
			else
			{
				lines.push(luaCall('addLuaSprite', [tag, 'false']));
				if (charsSeen > 0 && anchor != null)
				{
					orderLine = luaCall('setObjectOrder', [tag, luaCall('getObjectOrder', [anchor]) + ' + 1']);
					if (conds.length < 1)
						anchor = tag;
				}
			}

			var cond:String = conds.join(' and ');
			body.push('\t-- ' + name);
			if (cond.length > 0)
			{
				body.push('\tif ' + cond + ' then');
				for (l in lines)
					body.push('\t\t' + l);
				body.push('\tend');
				if (orderLine != null)
					order.push('\tif ' + cond + ' then ' + orderLine + ' end');
			}
			else
			{
				for (l in lines)
					body.push('\t' + l);
				if (orderLine != null)
					order.push('\t' + orderLine);
			}
			body.push('');
		}

		var result:Array<String> = [
			'--@editor-meta',
			'--@objects ' + haxe.Json.stringify(collectObjects()),
			'--@end-editor-meta',
			'-- Generated by the Stage Editor',
			'-- Stage: ' + stageName,
			'',
			'function onCreate()'
		];
		if (body.length < 1)
			result.push('\t-- no sprites');
		for (l in body)
			result.push(l);
		if (order.length > 0)
		{
			result.push('\t-- layering between characters');
			for (l in order)
				result.push(l);
		}
		result.push('end');
		result.push('');
		return result.join('\n');
	}

	var _file:FileReference;

	function onSaveComplete(_):Void
	{
		if (_file == null)
			return;
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.notice('Successfully saved file.');

		if (_pendingLua != null)
		{
			var luaContent:String = _pendingLua;
			var luaName:String = _pendingLuaName;
			_pendingLua = _pendingLuaName = null;
			startSave(luaContent, luaName);
		}
	}

	function onSaveCancel(_):Void
	{
		if (_file == null)
			return;
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		_pendingLua = _pendingLuaName = null;
	}

	function onSaveError(_):Void
	{
		if (_file == null)
			return;
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		_pendingLua = _pendingLuaName = null;
		FlxG.log.error('Problem saving file');
	}

	var _makeNewSprite = null;

	public function loadImage(onNewSprite:String = null)
	{
		if (_file != null)
			return;

		_makeNewSprite = onNewSprite;
		_file = new FileReference();
		_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.addEventListener(Event.CANCEL, onLoadCancel);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);

		final filters = [
			new FileFilter('PNG (Image)', '*.png'),
			new FileFilter('XML (Sparrow)', '*.xml'),
			new FileFilter('JSON (Aseprite)', '*.json'),
			new FileFilter('TXT (Packer)', '*.txt')
		];
		_file.browse(#if !mac filters #else [] #end);
	}

	private function onLoadComplete(_):Void
	{
		if (_file == null)
			return;
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);

		#if sys
		var fullPath:String = null;
		@:privateAccess
		if (_file.__path != null)
			fullPath = _file.__path;

		function loadSprite(imageToLoad:String)
		{
			if (_makeNewSprite != null)
			{
				if (_makeNewSprite == 'animatedSprite'
					&& !Paths.fileExists('images/$imageToLoad.xml', TEXT)
					&& !Paths.fileExists('images/$imageToLoad.json', TEXT)
					&& !Paths.fileExists('images/$imageToLoad.txt', TEXT)
					&& findImageFile(imageToLoad, 'xml') == null
					&& findImageFile(imageToLoad, 'json') == null
					&& findImageFile(imageToLoad, 'txt') == null)
				{
					showOutput('No Animation file found with the same name of the image!', true);
					_makeNewSprite = null;
					_file = null;
					return;
				}
				insertMeta(new StageEditorMetaSprite({type: _makeNewSprite, name: findUnoccupiedName()}, new ModchartSprite()));
			}
			var selected = getSelected();
			tryLoadImage(selected, imageToLoad);

			if (_makeNewSprite != null)
			{
				selected.sprite.x = Math.round(FlxG.camera.scroll.x + FlxG.width / 2 - selected.sprite.width / 2);
				selected.sprite.y = Math.round(FlxG.camera.scroll.y + FlxG.height / 2 - selected.sprite.height / 2);
				posTxt.visible = true;
				posTxt.text = 'X: ${selected.sprite.x}\nY: ${selected.sprite.y}';
			}
			_makeNewSprite = null;
		}
		_file = null;

		if (fullPath != null)
		{
			fullPath = fullPath.replace('\\', '/');
			var exePath = Sys.getCwd().replace('\\', '/');
			#if android
			var externalPath = StorageUtil.getExternalStorageDirectory();
			#end
			if (fullPath.startsWith(exePath))
			{
				fullPath = fullPath.substr(exePath.length);
				if ((fullPath.startsWith('assets/') #if MODS_ALLOWED || fullPath.startsWith('mods/') #end)
					&& fullPath.contains('/images/'))
				{
					loadSprite(fullPath.substring(fullPath.indexOf('/images/') + '/images/'.length, fullPath.lastIndexOf('.')));
					return;
				}
			}
			#if android
			else if (fullPath.startsWith(externalPath))
			{
				fullPath = fullPath.substr(externalPath.length);
				if ((fullPath.startsWith('assets/') #if MODS_ALLOWED || fullPath.startsWith('mods/') #end)
					&& fullPath.contains('/images/'))
				{
					loadSprite(fullPath.substring(fullPath.indexOf('/images/') + '/images/'.length, fullPath.lastIndexOf('.')));
					return;
				}
			}
			#end

			createPopup.visible = createPopup.active = false;
			#if MODS_ALLOWED
			var modFolder:String = (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0) ? Paths.mods('${Mods.currentModDirectory}/images/') : Paths.mods('images/');
			openSubState(new BasePrompt(480, 160, 'This file is not inside Psych Engine.', function(state:BasePrompt)
			{
				var txt:FlxText = new FlxText(0, state.bg.y + 60, 460, 'Copy to: "$modFolder"?', 11);
				txt.alignment = CENTER;
				txt.screenCenter(X);
				txt.cameras = state.cameras;
				state.add(txt);

				var btnY = 390;
				var btn:PsychUIButton = new PsychUIButton(0, btnY, 'OK', function()
				{
					var fileName:String = fullPath.substring(fullPath.lastIndexOf('/') + 1, fullPath.lastIndexOf('.'));
					var pathNoExt:String = fullPath.substring(0, fullPath.lastIndexOf('.'));
					function saveFile(ext:String)
					{
						var p1:String = '$pathNoExt.$ext';
						var p2:String = modFolder + '$fileName.$ext';
						trace(p1, p2);
						if (FileSystem.exists(p1))
							File.saveBytes(p2, File.getBytes(p1));
					}

					FileSystem.createDirectory(modFolder);
					saveFile('png');
					saveFile('xml');
					saveFile('txt');
					saveFile('json');
					loadSprite(fileName);
					state.close();
				});
				btn.normalStyle.bgColor = FlxColor.GREEN;
				btn.normalStyle.textColor = FlxColor.WHITE;
				btn.screenCenter(X);
				btn.x -= 100;
				btn.cameras = state.cameras;
				state.add(btn);

				var btn:PsychUIButton = new PsychUIButton(0, btnY, 'Cancel', function()
				{
					_makeNewSprite = null;
					state.close();
				});
				btn.screenCenter(X);
				btn.x += 100;
				btn.cameras = state.cameras;
				state.add(btn);
			}));
			#else
			showOutput('ERROR! File cannot be used, move it to "assets" and recompile.', true);
			#end
		}
		_file = null;
		#else
		trace('File couldn\'t be loaded! You aren\'t on Desktop, are you?');
		#end
	}

	function tryLoadImage(spr:StageEditorMetaSprite, imgPath:String)
	{
		if (spr == null || StageData.reservedNames.contains(spr.type) || spr.type == 'square' || imgPath == null)
			return;

		spr.image = imgPath;
		updateSelectedUI();
	}

	private function onLoadCancel(_):Void
	{
		if (_file == null)
			return;
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file = null;

		if (_makeNewSprite != null)
		{
			createPopup.visible = createPopup.active = false;
			_makeNewSprite = null;
		}
		trace('Cancelled file loading.');
	}

	private function onLoadError(_):Void
	{
		if (_file == null)
			return;
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file = null;

		if (_makeNewSprite != null)
		{
			createPopup.visible = createPopup.active = false;
			_makeNewSprite = null;
		}
		trace('Problem loading file');
	}

	override function destroy()
	{
		destroySubStates = true;
		if (animationEditor != null)
			animationEditor = FlxDestroyUtil.destroy(animationEditor);
		super.destroy();
	}
}

class StageEditorMetaSprite
{
	public var sprite:FlxSprite;
	public var visible(get, set):Bool;

	function get_visible() return sprite.visible;
	function set_visible(v:Bool) return (sprite.visible = v);

	public var type:String;
	public var name:String;
	public var filters:LoadFilters = (LOW_QUALITY) | (HIGH_QUALITY);
	public var x(get, set):Float;
	public var y(get, set):Float;
	public var alpha(get, set):Float;
	public var angle(get, set):Float;

	function get_x() return sprite.x;
	function set_x(v:Float) return (sprite.x = v);
	function get_y() return sprite.y;
	function set_y(v:Float) return (sprite.y = v);
	function get_alpha() return sprite.alpha;
	function set_alpha(v:Float) return (sprite.alpha = v);
	function get_angle() return sprite.angle;
	function set_angle(v:Float) return (sprite.angle = v);

	public var color(default, set):String = 'FFFFFF';

	function set_color(v:String)
	{
		sprite.color = CoolUtil.colorFromString(v);
		return (color = v);
	}

	public var image(default, set):String = 'unknown';

	function set_image(v:String)
	{
		var loaded:Bool = false;
		try
		{
			switch (type)
			{
				case 'sprite':
					var g = Paths.image(v);
					if (g != null)
					{
						sprite.loadGraphic(g);
						loaded = (sprite.graphic != null);
					}
				case 'animatedSprite':
					var fr = Paths.getAtlas(v);
					if (fr != null)
					{
						sprite.frames = fr;
						loaded = (sprite.frames != null);
					}
			}
		}
		catch (e:Dynamic) {}

		// Paths couldn't find it (other mod folder, assets/<week>/images, subfolders...): search every images folder
		if (!loaded && (type == 'sprite' || type == 'animatedSprite'))
			loaded = StageEditorState.loadImageFromDisk(sprite, v, type == 'animatedSprite');

		if ((type == 'sprite' || type == 'animatedSprite') && (!loaded || sprite.graphic == null || sprite.frames == null))
		{
			trace('Could not load image "$v" for sprite "$name"');
			sprite.makeGraphic(200, 200, FlxColor.MAGENTA);
		}
		sprite.updateHitbox();
		return (image = v);
	}

	public var scroll:Array<Float> = [1, 1];

	public function setScrollFactor(scrX:Null<Float> = null, scrY:Null<Float> = null)
	{
		scroll[0] = (scrX != null ? scrX : scroll[0]);
		scroll[1] = (scrY != null ? scrY : scroll[1]);
		sprite.scrollFactor.set(scroll[0], scroll[1]);
	}

	public var scale:Array<Float> = [1, 1];
	public var antialiasing(default, set):Bool = true;

	function set_antialiasing(v:Bool)
	{
		sprite.antialiasing = (v && ClientPrefs.data.antialiasing);
		return (antialiasing = v);
	}

	public function setScale(wid:Null<Float> = null, hei:Null<Float> = null)
	{
		scale[0] = (wid != null ? wid : scale[0]);
		scale[1] = (hei != null ? hei : scale[1]);
		sprite.scale.set(scale[0], scale[1]);
		sprite.updateHitbox();
	}

	public var flipX(get, set):Bool;
	public var flipY(get, set):Bool;

	function get_flipX() return sprite.flipX;
	function set_flipX(v:Bool) return (sprite.flipX = (v && type != 'square'));
	function get_flipY() return sprite.flipY;
	function set_flipY(v:Bool) return (sprite.flipY = (v && type != 'square'));

	public var firstAnimation:String;
	public var animations:Array<AnimArray>;

	public function new(data:Dynamic, spr:FlxSprite)
	{
		this.sprite = spr;
		if (data == null)
			return;

		this.type = data.type;
		switch (this.type)
		{
			case 'sprite', 'square', 'animatedSprite':
				for (v in ['name', 'image', 'scale', 'scroll', 'color', 'filters', 'antialiasing'])
				{
					var dat:Dynamic = Reflect.field(data, v);
					if (dat != null)
						Reflect.setField(this, v, dat);
				}

				if (this.type == 'animatedSprite')
				{
					this.animations = data.animations;
					this.firstAnimation = data.firstAnimation;

					// make sure the animations exist (the image may have been loaded from disk)
					if (this.animations != null && sprite.animation != null)
					{
						for (anim in this.animations)
						{
							if (anim == null || sprite.animation.getByName(anim.anim) != null)
								continue;
							if (anim.indices != null && anim.indices.length > 0)
								sprite.animation.addByIndices(anim.anim, anim.name, anim.indices, '', anim.fps, anim.loop);
							else
								sprite.animation.addByPrefix(anim.anim, anim.name, anim.fps, anim.loop);
						}
						if (this.firstAnimation != null && sprite.animation.getByName(this.firstAnimation) != null)
							sprite.animation.play(this.firstAnimation, true);
					}
				}
		}
	}

	public function formatToJson()
	{
		if (type == null) return null;
		var obj:Dynamic = {type: type};
		switch (type)
		{
			case 'square', 'sprite', 'animatedSprite':
				obj.name = name;
				obj.x = x;
				obj.y = y;
				obj.scale = scale;
				obj.scroll = scroll;
				obj.alpha = alpha;
				obj.angle = angle;
				obj.color = color;
				obj.filters = filters;

				if (type != 'square')
				{
					obj.flipX = flipX;
					obj.flipY = flipY;
					obj.image = image;
					obj.antialiasing = antialiasing;
					if (type == 'animatedSprite')
					{
						obj.animations = animations;
						obj.firstAnimation = firstAnimation;
					}
				}
		}
		return obj;
	}

	public function isShown(curFilters:LoadFilters):Bool
		return ((curFilters & filters) != 0 || StageData.reservedNames.contains(type));

	public function update(curFilters:LoadFilters, elapsed:Float)
	{
		if ((curFilters & filters) != 0 || StageData.reservedNames.contains(type))
			sprite.update(elapsed);
	}

	public function draw(curFilters:LoadFilters)
	{
		if ((curFilters & filters) != 0 || StageData.reservedNames.contains(type))
			sprite.draw();
	}
}

class StageEditorExitPrompt extends MusicBeatSubstate
{
	public function new()
	{
		super();
		var bg:FlxSprite = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		bg.scale.set(FlxG.width, FlxG.height);
		bg.updateHitbox();
		bg.alpha = 0.6;
		add(bg);

		var txt:FlxText = new FlxText(0, FlxG.height / 2 - 60, FlxG.width, "Unsaved progress!\nAre you sure you want to exit?", 24);
		txt.setFormat(null, 24, FlxColor.WHITE, CENTER, OUTLINE_FAST, FlxColor.BLACK);
		txt.borderSize = 1;
		add(txt);

		var btnYes:PsychUIButton = new PsychUIButton(FlxG.width / 2 - 110, FlxG.height / 2 + 20, 'Yes', function()
		{
			close();
			// FIX: Replaced FlxTimer.globals.run with new FlxTimer().start
			new FlxTimer().start(0.01, function(_) {
				MusicBeatState.switchState(new states.editors.MasterEditorMenu());
			});
		});
		btnYes.normalStyle.bgColor = FlxColor.RED;
		btnYes.normalStyle.textColor = FlxColor.WHITE;
		btnYes.cameras = [cast(FlxG.state, StageEditorState).camHUD];
		add(btnYes);

		var btnNo:PsychUIButton = new PsychUIButton(FlxG.width / 2 + 10, FlxG.height / 2 + 20, 'No', function()
		{
			close();
		});
		btnNo.cameras = [cast(FlxG.state, StageEditorState).camHUD];
		add(btnNo);
	}
}

class StageEditorAnimationSubstate extends MusicBeatSubstate
{
	var bg:FlxSprite;
	var originalZoom:Float;
	var originalCamPoint:FlxPoint;
	var originalPosition:FlxPoint;
	var originalCamTarget:FlxObject;
	var originalAlpha:Float = 1;

	public var target:StageEditorMetaSprite;

	var curAnim:Int = 0;
	var animsTxtGroup:FlxTypedGroup<FlxText>;

	var UI_animationbox:PsychUIBox;
	var camHUD:FlxCamera = cast(FlxG.state, StageEditorState).camHUD;

	public function new()
	{
		controls.isInSubstate = true;
		super();

		var grid:FlxBackdrop = new FlxBackdrop(FlxGridOverlay.createGrid(50, 50, 100, 100, true, 0xFFAAAAAA, 0xFF666666));
		add(grid);

		animsTxtGroup = new FlxTypedGroup<FlxText>();
		animsTxtGroup.cameras = [camHUD];
		add(animsTxtGroup);

		UI_animationbox = new PsychUIBox(FlxG.width - 320, 20, 300, 250, ['Animations']);
		UI_animationbox.cameras = [camHUD];
		UI_animationbox.scrollFactor.set();
		add(UI_animationbox);
		addAnimationsUI();

		openCallback = function()
		{
			curAnim = 0;
			originalZoom = FlxG.camera.zoom;
			originalCamPoint = FlxPoint.get(FlxG.camera.scroll.x, FlxG.camera.scroll.y);
			originalPosition = FlxPoint.get(target.x, target.y);
			originalCamTarget = FlxG.camera.target;
			originalAlpha = target.alpha;
			FlxG.camera.zoom = 0.5;
			FlxG.camera.scroll.set(0, 0);

			target.alpha = 1;
			target.sprite.screenCenter();
			add(target.sprite);
			reloadAnimList();
		};

		closeCallback = function()
		{
			FlxG.camera.zoom = originalZoom;
			FlxG.camera.scroll.set(originalCamPoint.x, originalCamPoint.y);
			FlxG.camera.target = originalCamTarget;

			target.x = originalPosition.x;
			target.y = originalPosition.y;
			target.alpha = originalAlpha;
			remove(target.sprite);

			if (target.animations.length > 0)
			{
				if (target.firstAnimation == null)
					target.firstAnimation = target.animations[0].anim;
				playAnim(target.firstAnimation);
			}

			if (originalCamPoint != null)
			{
				originalCamPoint.put();
				originalCamPoint = null;
			}
			if (originalPosition != null)
			{
				originalPosition.put();
				originalPosition = null;
			}
		};

		addTouchPad('LEFT_FULL', 'CHARACTER_EDITOR');
		addTouchPadCamera();
	}

	var animationDropDown:PsychUIDropDownMenu;
	var animationInputText:PsychUIInputText;
	var animationNameInputText:PsychUIInputText;
	var animationIndicesInputText:PsychUIInputText;
	var animationFramerate:PsychUINumericStepper;
	var animationLoopCheckBox:PsychUICheckBox;
	var mainAnimTxt:FlxText;

	function addAnimationsUI()
	{
		var tab_group = UI_animationbox.getTab('Animations').menu;

		animationInputText = new PsychUIInputText(15, 85, 80, '', 8);
		animationNameInputText = new PsychUIInputText(animationInputText.x, animationInputText.y + 35, 150, '', 8);
		animationIndicesInputText = new PsychUIInputText(animationNameInputText.x, animationNameInputText.y + 40, 250, '', 8);
		animationFramerate = new PsychUINumericStepper(animationInputText.x + 170, animationInputText.y, 1, 24, 0, 240, 0);
		animationLoopCheckBox = new PsychUICheckBox(animationNameInputText.x + 170, animationNameInputText.y - 1, 'Should it Loop?', 100);

		animationDropDown = new PsychUIDropDownMenu(15, animationInputText.y - 55, [''], function(selectedAnimation:Int, pressed:String)
		{
			var anim:AnimArray = target.animations[selectedAnimation];
			if (anim == null)
				return;

			animationInputText.text = anim.anim;
			animationNameInputText.text = anim.name;
			animationLoopCheckBox.checked = anim.loop;
			animationFramerate.value = anim.fps;

			var indicesStr:String = anim.indices.toString();
			animationIndicesInputText.text = indicesStr.substr(1, indicesStr.length - 2);
		});

		mainAnimTxt = new FlxText(160, animationDropDown.y - 18, 0, 'Main Anim.: ');
		var initAnimButton:PsychUIButton = new PsychUIButton(160, animationDropDown.y, 'Main Animation', function()
		{
			var anim:AnimArray = target.animations[curAnim];
			if (anim == null)
				return;

			mainAnimTxt.text = 'Main Anim.: ${anim.anim}';
			target.firstAnimation = anim.anim;
		});
		tab_group.add(mainAnimTxt);
		tab_group.add(initAnimButton);

		var addUpdateButton:PsychUIButton = new PsychUIButton(40, animationIndicesInputText.y + 35, 'Add/Update', function()
		{
			if (animationInputText.text == '')
				return;

			var indices:Array<Int> = [];
			var indicesStr:Array<String> = animationIndicesInputText.text.trim().split(',');
			if (indicesStr.length > 1)
			{
				for (i in 0...indicesStr.length)
				{
					var index:Int = Std.parseInt(indicesStr[i]);
					if (indicesStr[i] != null && indicesStr[i] != '' && !Math.isNaN(index) && index > -1)
					{
						indices.push(index);
					}
				}
			}

			var lastAnim:String = (target.animations[curAnim] != null) ? target.animations[curAnim].anim : '';
			var lastOffsets:Array<Int> = null;
			for (anim in target.animations)
				if (animationInputText.text == anim.anim)
				{
					lastOffsets = anim.offsets;
					cast(target.sprite, ModchartSprite).animOffsets.remove(animationInputText.text);
					target.sprite.animation.remove(animationInputText.text);
					target.animations.remove(anim);
				}

			var addedAnim:AnimArray = {
				anim: animationInputText.text,
				name: animationNameInputText.text,
				fps: Math.round(animationFramerate.value),
				loop: animationLoopCheckBox.checked,
				indices: indices,
				offsets: lastOffsets
			};

			if (addedAnim.indices != null && addedAnim.indices.length > 0)
				target.sprite.animation.addByIndices(addedAnim.anim, addedAnim.name, addedAnim.indices, '', addedAnim.fps, addedAnim.loop);
			else
				target.sprite.animation.addByPrefix(addedAnim.anim, addedAnim.name, addedAnim.fps, addedAnim.loop);

			target.animations.push(addedAnim);
			reloadAnimList();
			playAnim(addedAnim.anim, true);

			curAnim = target.animations.length - 1;
			updateTextColors();
		});

		var removeButton:PsychUIButton = new PsychUIButton(160, animationIndicesInputText.y + 35, 'Remove', function()
		{
			for (anim in target.animations)
			{
				if (animationInputText.text == anim.anim)
				{
					var targetSprite:ModchartSprite = cast(target.sprite, ModchartSprite);
					var resetAnim:Bool = false;
					if (targetSprite.animation.curAnim != null && anim.anim == targetSprite.animation.curAnim.name)
						resetAnim = true;

					if (targetSprite.animOffsets.exists(anim.anim))
						targetSprite.animOffsets.remove(anim.anim);

					target.animations.remove(anim);
					targetSprite.animation.remove(anim.anim);

					if (resetAnim && target.animations.length > 0)
					{
						curAnim = FlxMath.wrap(curAnim, 0, target.animations.length - 1);
						playAnim(target.animations[curAnim].anim, true);
						updateTextColors();
					}
					else if (target.animations.length < 1)
						target.sprite.animation.curAnim = null;

					reloadAnimList();
					break;
				}
			}
		});

		tab_group.add(new FlxText(animationDropDown.x, animationDropDown.y - 18, 0, 'Animations:'));
		tab_group.add(new FlxText(animationInputText.x, animationInputText.y - 18, 0, 'Animation name:'));
		tab_group.add(new FlxText(animationFramerate.x, animationFramerate.y - 18, 0, 'Framerate:'));
		tab_group.add(new FlxText(animationNameInputText.x, animationNameInputText.y - 18, 0, 'Animation Symbol Name/Tag:'));
		tab_group.add(new FlxText(animationIndicesInputText.x, animationIndicesInputText.y - 18, 0, 'ADVANCED - Animation Indices:'));

		tab_group.add(animationInputText);
		tab_group.add(animationNameInputText);
		tab_group.add(animationIndicesInputText);
		tab_group.add(animationFramerate);
		tab_group.add(animationLoopCheckBox);
		tab_group.add(addUpdateButton);
		tab_group.add(removeButton);
		tab_group.add(animationDropDown);
	}

	function reloadAnimList()
	{
		if (target.animations == null)
			target.animations = [];
		else if (target.animations.length > 0)
			playAnim(target.animations[0].anim, true);
		curAnim = 0;

		for (text in animsTxtGroup)
			text.kill();

		var spr:ModchartSprite = cast(target.sprite, ModchartSprite);
		if (target.animations.length > 0)
		{
			if (target.firstAnimation == null || !target.sprite.animation.exists(target.firstAnimation))
				target.firstAnimation = target.animations[0].anim;

			mainAnimTxt.text = 'Main Anim.: ${target.firstAnimation}';
		}
		else
		{
			target.firstAnimation = null;
			mainAnimTxt.text = '(No Main Animation)';
		}

		for (num => anim in target.animations)
		{
			var text:FlxText = animsTxtGroup.recycle(FlxText);
			text.x = 10;
			text.y = 32 + (20 * num);
			text.fieldWidth = 400;
			text.fieldHeight = 20;
			if (anim.offsets != null)
				text.text = '${anim.anim}: ${spr.animOffsets.get(anim.anim)}';
			else
				text.text = '${anim.anim}: No offsets';

			text.setFormat(null, 16, FlxColor.WHITE, LEFT, OUTLINE_FAST, FlxColor.BLACK);
			text.scrollFactor.set();
			text.borderSize = 1;
			animsTxtGroup.add(text);
		}
		updateTextColors();
		reloadAnimationDropDown();
	}

	function reloadAnimationDropDown()
	{
		var animList:Array<String> = [];
		for (anim in target.animations)
			animList.push(anim.anim);
		if (animList.length < 1)
			animList.push('NO ANIMATIONS');

		animationDropDown.list = animList;
	}

	inline function updateTextColors()
	{
		for (num => text in animsTxtGroup)
		{
			text.color = FlxColor.WHITE;
			if (num == curAnim)
				text.color = FlxColor.LIME;
		}
	}

	function playAnim(name:String, force:Bool = false)
	{
		var spr:ModchartSprite = cast(target.sprite, ModchartSprite);
		spr.playAnim(name, force);
		if (!spr.animOffsets.exists(name))
			spr.updateHitbox();
	}

	final minZoom = 0.25;
	final maxZoom = 2;
	var holdingArrowsTime:Float = 0;
	var holdingArrowsElapsed:Float = 0;

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (PsychUIInputText.focusOn != null)
			return;

		if (target.animations.length > 1)
		{
			var changedAnim:Bool = false;
			if (FlxG.keys.justPressed.W || touchPad.buttonUp.justPressed && (changedAnim = true))
				curAnim--;
			else if (FlxG.keys.justPressed.S || touchPad.buttonDown.justPressed && (changedAnim = true))
				curAnim++;
			else if (FlxG.keys.justPressed.SPACE)
				changedAnim = true;

			if (changedAnim)
			{
				curAnim = FlxMath.wrap(curAnim, 0, target.animations.length - 1);
				playAnim(target.animations[curAnim].anim, true);
				updateTextColors();
			}
		}

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

		if (target.sprite.animation.curAnim != null)
		{
			var spr:ModchartSprite = cast(target.sprite, ModchartSprite);
			var anim:String = spr.animation.curAnim.name;
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
			if (moveKeysP.contains(true) && !touchPad.buttonG.pressed)
			{
				if (spr.animOffsets.get(anim) != null)
				{
					spr.offset.x += ((moveKeysP[0] ? 1 : 0) - (moveKeysP[1] ? 1 : 0)) * shiftMultBig;
					spr.offset.y += ((moveKeysP[2] ? 1 : 0) - (moveKeysP[3] ? 1 : 0)) * shiftMultBig;
				}
				else
					spr.offset.x = spr.offset.y = 0;
				changedOffset = true;
			}

			if (moveKeys.contains(true) && !touchPad.buttonG.pressed)
			{
				holdingArrowsTime += elapsed;
				if (holdingArrowsTime > 0.6)
				{
					holdingArrowsElapsed += elapsed;
					while (holdingArrowsElapsed > (1 / 60))
					{
						if (spr.animOffsets.get(anim) != null)
						{
							spr.offset.x += ((moveKeys[0] ? 1 : 0) - (moveKeys[1] ? 1 : 0)) * shiftMultBig;
							spr.offset.y += ((moveKeys[2] ? 1 : 0) - (moveKeys[3] ? 1 : 0)) * shiftMultBig;
						}
						else
							spr.offset.x = spr.offset.y = 0;
						holdingArrowsElapsed -= (1 / 60);
						changedOffset = true;
					}
				}
			}
			else
				holdingArrowsTime = 0;

			if (FlxG.mouse.pressedRight && (FlxG.mouse.deltaScreenX != 0 || FlxG.mouse.deltaScreenY != 0))
			{
				spr.offset.x -= FlxG.mouse.deltaScreenX;
				spr.offset.y -= FlxG.mouse.deltaScreenY;
				changedOffset = true;
			}

			if (FlxG.keys.justPressed.R || touchPad.buttonZ.justPressed && FlxG.keys.pressed.CONTROL || touchPad.buttonC.pressed)
			{
				target.animations[curAnim].offsets = null;
				spr.animOffsets.remove(anim);
				spr.updateHitbox();
				animsTxtGroup.members[curAnim].text = '${anim}: No offsets';
			}

			if (changedOffset)
			{
				var offX = Math.round(spr.offset.x);
				var offY = Math.round(spr.offset.y);

				spr.addOffset(anim, offX, offY);
				target.animations[curAnim].offsets = [offX, offY];
				animsTxtGroup.members[curAnim].text = '${anim}: ${spr.animOffsets.get(anim)}';
			}
		}
		else
		{
			holdingArrowsTime = 0;
			holdingArrowsElapsed = 0;
		}

		var camX:Float = 0;
		var camY:Float = 0;
		var camMove:Float = elapsed * 500 * shiftMult * ctrlMult;
		if (FlxG.keys.pressed.J || (touchPad.buttonLeft.pressed && touchPad.buttonG.pressed))
			camX -= camMove;
		if (FlxG.keys.pressed.K || (touchPad.buttonDown.pressed && touchPad.buttonG.pressed))
			camY += camMove;
		if (FlxG.keys.pressed.L || (touchPad.buttonRight.pressed && touchPad.buttonG.pressed))
			camX += camMove;
		if (FlxG.keys.pressed.I || (touchPad.buttonUp.pressed && touchPad.buttonG.pressed))
			camY -= camMove;

		if (camX != 0 || camY != 0)
		{
			FlxG.camera.scroll.x += camX;
			FlxG.camera.scroll.y += camY;
		}

		if (FlxG.keys.justPressed.R || touchPad.buttonZ.justPressed && !FlxG.keys.pressed.CONTROL)
			FlxG.camera.zoom = 0.5;
		else if (FlxG.keys.pressed.E || touchPad.buttonX.pressed && FlxG.camera.zoom < maxZoom)
			FlxG.camera.zoom = Math.min(maxZoom, FlxG.camera.zoom + elapsed * FlxG.camera.zoom * shiftMult * ctrlMult);
		else if (FlxG.keys.pressed.Q || touchPad.buttonY.pressed && FlxG.camera.zoom > minZoom)
			FlxG.camera.zoom = Math.max(minZoom, FlxG.camera.zoom - elapsed * FlxG.camera.zoom * shiftMult * ctrlMult);

		if (FlxG.keys.justPressed.ESCAPE #if android || FlxG.android.justReleased.BACK #end || touchPad.buttonB.justPressed)
		{
			persistentDraw = true;
			controls.isInSubstate = false;
			close();
		}
	}
}

typedef PngEntry =
{
	var name:String; // path relative to the images folder, without extension
	var hasXml:Bool;
	var root:String; // images folder it was found in (e.g. 'mods/images/', 'assets/shared/images/')
}
