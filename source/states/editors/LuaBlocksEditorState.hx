package states.editors;

import flixel.FlxBasic;
import haxe.io.Path;
import lime.system.Clipboard;
import lime.ui.FileDialog;
import lime.ui.FileDialogType;
import states.editors.content.Prompt;
import states.editors.eventcreator.EventDef.BlockDef;
import states.editors.eventcreator.EventDef.BlockFieldDef;
import states.editors.luablocks.LuaBlocksCodegen;
import states.editors.luablocks.LuaBlocksPalette;
import states.editors.luablocks.LuaBlocksProject;

using Lambda;

class LuaBlocksEditorState extends MusicBeatState
{
	static inline var PANEL:Int = 0xFF202335;
	static inline var INK:Int = 0xFFF3F1FF;
	static inline var MUTED:Int = 0xFFAFB4D0;
	static inline var ACCENT:Int = 0xFFA394FF;
	static inline var HAT:Int = 0xFFC98631;
	static inline var MARGIN:Int = 20;
	static inline var LEFT_W:Int = 240;
	static inline var RIGHT_W:Int = 330;
	static inline var STACK_Y:Int = 299;
	static inline var PALETTE_Y:Int = 192;
	static inline var ROW:Int = 32;
	static inline var FIELDS:Int = 5;

	final ui = new FlxTypedGroup<FlxBasic>();
	final overlay = new FlxTypedGroup<FlxBasic>();
	final definitions:Map<String, BlockDef> = [];
	var palette:Array<BlockDef> = [];
	var filtered:Array<BlockDef> = [];
	var project = new LuaBlocksProject();
	var selectedHat:LuaBlockHat = LuaBlocksProject.hats[0];
	var selectedStack:LuaBlockStack;
	var selectedBlock:LuaBlock;
	var dirty:Bool = false;
	var modRoot:String;
	var openDialog:FileDialog;
	var pendingPath:String;
	var browseCancelled:Bool = false;
	var savedPath:String;
	var savedContent:String;

	var centerX:Int;
	var centerW:Int;
	var rightX:Int;
	var footerY:Int;
	var font:String;
	var nameInput:PsychUIInputText;
	var songInput:PsychUIInputText;
	var filterInput:PsychUIInputText;
	var filterLabel:FlxText;
	var destination:FlxText;
	var status:FlxText;
	var stackHat:LuaBlockTile;
	var stackEmpty:FlxText;
	var stackPosition:FlxText;
	var stackUp:PsychUIButton;
	var stackDown:PsychUIButton;
	var paletteUp:PsychUIButton;
	var paletteDown:PsychUIButton;
	var paletteEmpty:FlxText;
	var inspectTitle:FlxText;
	var blockDescription:FlxText;
	var removeBlockButton:PsychUIButton;
	var removeStackButton:PsychUIButton;
	var hats:Array<LuaBlockTile> = [];
	var paletteTiles:Array<LuaBlockTile> = [];
	var stackTiles:Array<LuaBlockTile> = [];
	var fieldLabels:Array<FlxText> = [];
	var fieldInputs:Array<PsychUIInputText> = [];
	var fieldPickers:Array<PsychUIButton> = [];
	var sourceButtons:Array<PsychUIButton> = [];
	var paletteScroll:Int = 0;
	var stackScroll:Int = 0;
	var dragDef:BlockDef;
	var dragBlock:LuaBlock;
	var dragStartX:Float;
	var dragStartY:Float;
	var dragging:Bool = false;
	var dragScroll:Float = 0;
	var ghost:LuaBlockTile;
	var insertMark:FlxSprite;

	var overlayMode:String;
	var choiceValues:Array<String> = [];
	var choiceLabels:Array<String> = [];
	var choiceAction:String->Void;
	var choiceRows:Array<PsychUIButton> = [];
	var overlayScroll:Int = 0;
	var previewLines:Array<String> = [];
	var previewText:FlxText;
	var previewPosition:FlxText;
	var previewRows:Int;
	var previewCode:String;

	override function create():Void
	{
		super.create();
		persistentUpdate = false;
		FlxG.camera.bgColor = 0xFF151725;
		FlxG.mouse.visible = true;
		#if DISCORD_ALLOWED
		DiscordClient.changePresence('Lua Blocks Editor', null);
		#end
		font = Paths.font('NotoSans-Medium.ttf');
		modRoot = Paths.getModDirectory(Mods.currentModDirectory);
		centerX = LEFT_W + MARGIN * 2;
		rightX = FlxG.width - RIGHT_W - MARGIN;
		centerW = rightX - centerX - MARGIN;
		footerY = FlxG.height - 34;
		add(ui);
		add(overlay);
		buildToolbar();
		buildPalette();
		buildWorkspace();
		buildInspector();
		status = label(ui, MARGIN, footerY + 4, FlxG.width - MARGIN * 2, '', 13, MUTED);
		insertMark = box(ui, 0, 0, centerW - 44, 3, ACCENT);
		insertMark.visible = false;
		ghost = new LuaBlockTile(0, 0, 220, ROW - 4, font, true);
		ghost.visible = false;
		ui.add(ghost);
		loadProject(project);
		try
		{
			palette = LuaBlocksPalette.load();
			for (def in palette)
				definitions.set(def.id, def);
			filterPalette('');
		}
		catch (e:Dynamic)
			showStatus(Std.string(e), true);
	}

	function buildToolbar():Void
	{
		box(ui, 0, 0, FlxG.width, 98, PANEL);
		button(ui, MARGIN, 14, 'Back', 68, leave);
		label(ui, 102, 10, 350, 'Lua Blocks Editor', 24);
		var x = FlxG.width - 444;
		button(ui, x, 14, 'New', 68, () -> confirmDiscard(() -> loadProject(new LuaBlocksProject())));
		button(ui, x + 76, 14, 'Open Lua', 96, () -> confirmDiscard(browse));
		button(ui, x + 180, 14, 'Lua preview', 116, showPreview);
		button(ui, x + 304, 14, 'Export Lua', 120, exportScript, ACCENT);
		label(ui, MARGIN, 47, 198, 'Script name', 12, MUTED);
		nameInput = input(MARGIN, 66, 198, 70, value ->
		{
			project.name = value;
			dirty = true;
			refreshDestination();
		});
		label(ui, 234, 47, 254, 'Song (optional)', 12, MUTED);
		songInput = input(234, 66, 254, 100, value ->
		{
			project.song = value;
			dirty = true;
			refreshDestination();
		});
		label(ui, 506, 47, 400, 'EXPORT DESTINATION', 12, MUTED);
		destination = label(ui, 506, 65, FlxG.width - 526, '', 14);
		destination.textField.wordWrap = false;
	}

	function buildPalette():Void
	{
		box(ui, MARGIN, 112, LEFT_W, footerY - 120, PANEL);
		label(ui, MARGIN + 12, 120, 140, 'Blocks', 19);
		label(ui, MARGIN + 12, 151, 74, 'Filter', 12, MUTED);
		input(MARGIN + 70, 149, LEFT_W - 84, 40, filterPalette);
		paletteEmpty = label(ui, MARGIN + 12, PALETTE_Y, LEFT_W - 24, 'No matching blocks', 14, MUTED);
		paletteUp = button(ui, MARGIN + LEFT_W - 69, 123, '^', 25, () -> scrollPalette(-1));
		paletteDown = button(ui, MARGIN + LEFT_W - 38, 123, 'v', 25, () -> scrollPalette(1));
		for (i in 0...Std.int((footerY - PALETTE_Y - 12) / ROW))
		{
			var tile = new LuaBlockTile(MARGIN + 12, PALETTE_Y + i * ROW, LEFT_W - 24, ROW - 4, font, false);
			paletteTiles.push(tile);
			ui.add(tile);
		}
	}

	function buildWorkspace():Void
	{
		box(ui, centerX, 112, centerW, footerY - 120, 0xFF1B1E30);
		var width = Std.int((centerW - 32) / 4);
		for (i => hat in LuaBlocksProject.hats)
		{
			var tile = new LuaBlockTile(centerX + 12 + (i % 4) * width, 124 + Std.int(i / 4) * 33, width - 6, 29, font, false);
			hats.push(tile);
			ui.add(tile);
		}
		label(ui, centerX + 14, 194, centerW - 200, 'Stacks', 17);
		stackUp = button(ui, centerX + centerW - 206, 195, '<', 24, () -> cycleStack(-1));
		stackPosition = label(ui, centerX + centerW - 178, 199, 56, '', 13, MUTED);
		stackPosition.alignment = CENTER;
		stackDown = button(ui, centerX + centerW - 119, 195, '>', 24, () -> cycleStack(1));
		button(ui, centerX + centerW - 89, 195, '+ Stack', 76, () -> { addStack(); });
		filterLabel = label(ui, centerX + 14, 229, 180, '', 13, MUTED);
		filterInput = input(centerX + 174, 227, centerW - 263, 120, value ->
		{
			if (ensureStack())
			{
				selectedStack.filter = value;
				dirty = true;
			}
		});
		removeStackButton = button(ui, centerX + centerW - 89, 227, 'Remove', 76, removeStack);
		stackHat = new LuaBlockTile(centerX + 16, STACK_Y - 34, 230, 30, font, true);
		ui.add(stackHat);
		stackEmpty = label(ui, centerX + 26, STACK_Y + 6, centerW - 52, 'Drag blocks here, or click a block in the palette.', 16, MUTED);
		for (i in 0...Std.int((footerY - STACK_Y - 12) / ROW))
		{
			var tile = new LuaBlockTile(centerX + 24, STACK_Y + i * ROW, centerW - 48, ROW - 3, font, true);
			stackTiles.push(tile);
			ui.add(tile);
		}
	}

	function buildInspector():Void
	{
		box(ui, rightX, 112, RIGHT_W, footerY - 120, PANEL);
		label(ui, rightX + 14, 120, RIGHT_W - 28, 'Block settings', 19);
		inspectTitle = label(ui, rightX + 14, 151, RIGHT_W - 28, '', 17, ACCENT);
		blockDescription = label(ui, rightX + 14, 179, RIGHT_W - 28, '', 13, MUTED);
		for (i in 0...FIELDS)
		{
			var y = 238 + 62 * i;
			fieldLabels.push(label(ui, rightX + 14, y, RIGHT_W - 120, '', 13, MUTED));
			fieldInputs.push(input(rightX + 14, y + 20, RIGHT_W - 68, 500, value ->
			{
				var blockValue = selectedBlock.values[i];
				blockValue.text = value;
				dirty = true;
				refreshStackTiles();
			}));
			fieldPickers.push(button(ui, rightX + RIGHT_W - 48, y + 20, 'v', 34, () -> pickValue(i)));
			sourceButtons.push(button(ui, rightX + RIGHT_W - 101, y - 4, 'Use input', 87, () -> pickSource(i)));
		}
		removeBlockButton = button(ui, rightX + 14, footerY - 47, 'Remove block', 112, removeBlock, 0xFF523044);
	}

	function label(group:FlxTypedGroup<FlxBasic>, x:Float, y:Float, width:Float, value:String, size:Int, color:Int = INK):FlxText
	{
		var result = new FlxText(x, y, width, value, size);
		result.setFormat(font, size, color);
		group.add(result);
		return result;
	}

	function box(group:FlxTypedGroup<FlxBasic>, x:Float, y:Float, width:Int, height:Int, color:Int):FlxSprite
	{
		var sprite = new FlxSprite(x, y).makeGraphic(1, 1, FlxColor.WHITE);
		sprite.setGraphicSize(width, height);
		sprite.updateHitbox();
		sprite.color = color;
		group.add(sprite);
		return sprite;
	}

	function input(x:Int, y:Int, width:Int, limit:Int, onChange:String->Void):PsychUIInputText
	{
		var field = new PsychUIInputText(x, y, width, '', 14);
		field.broadcastInputTextEvent = false;
		field.behindText.color = 0xFFDCDCF0;
		field.maxLength = limit;
		field.onChange = (_, value) -> onChange(value);
		ui.add(field);
		return field;
	}

	function button(group:FlxTypedGroup<FlxBasic>, x:Int, y:Int, title:String, width:Int, action:Void->Void, fill:Int = 0xFF353953):PsychUIButton
	{
		var widget = new PsychUIButton(x, y, title, action, width, 26);
		widget.broadcastButtonEvent = false;
		widget.text.setFormat(font, 12, INK, CENTER);
		widget.resize(width, 26);
		widget.normalStyle = {bgColor: fill, textColor: fill == ACCENT ? 0xFF19152D : INK, bgAlpha: 1};
		widget.hoverStyle = {bgColor: 0xFF545A7A, textColor: INK, bgAlpha: 1};
		widget.clickStyle = {bgColor: 0xFF6556A6, textColor: INK, bgAlpha: 1};
		group.add(widget);
		return widget;
	}

	function showStatus(message:String, warning:Bool = false):Void
	{
		status.text = message;
		status.color = warning ? 0xFFFFAF9E : MUTED;
	}

	function loadProject(next:LuaBlocksProject):Void
	{
		PsychUIInputText.focusOn = null;
		project = next;
		savedPath = savedContent = null;
		dirty = false;
		nameInput.text = project.name;
		songInput.text = project.song;
		var first = project.stacks.find(stack -> stack.blocks.length > 0);
		selectStack(first == null ? LuaBlocksProject.hats[0] : LuaBlocksProject.getHat(first.hat), first);
		refreshDestination();
		showStatus('Drag to insert or reorder. Click a palette block to append it.');
	}

	function selectStack(hat:LuaBlockHat, ?stack:LuaBlockStack):Void
	{
		PsychUIInputText.focusOn = null;
		selectedHat = hat;
		selectedStack = stack ?? project.stacks.find(item -> item.hat == hat.id);
		selectedBlock = null;
		stackScroll = 0;
		refreshWorkspace();
		refreshInspector();
	}

	function ensureStack():Bool
		return selectedStack != null || addStack(false);

	function addStack(focusNew:Bool = true):Bool
	{
		if (project.stacks.length >= LuaBlocksProject.MAX_STACKS)
		{
			showStatus('This project has reached the stack limit.', true);
			return false;
		}
		var stack:LuaBlockStack = {hat: selectedHat.id, filter: '', blocks: []};
		project.stacks.push(stack);
		dirty = true;
		if (focusNew)
			selectStack(selectedHat, stack);
		else
		{
			selectedStack = stack;
			refreshWorkspace(false);
		}
		return true;
	}

	function cycleStack(change:Int):Void
	{
		var stacks = project.stacks.filter(stack -> stack.hat == selectedHat.id);
		if (stacks.length > 1)
			selectStack(selectedHat, stacks[FlxMath.wrap(stacks.indexOf(selectedStack) + change, 0, stacks.length - 1)]);
	}

	function removeStack():Void
	{
		var stack = selectedStack;
		if (stack == null)
			return;
		var remove = () ->
		{
			project.stacks.remove(stack);
			dirty = true;
			selectStack(selectedHat);
		};
		if (stack.blocks.length == 0)
			remove();
		else
			openSubState(new Prompt('Remove this stack and all its blocks?', remove));
	}

	function removeBlock():Void
	{
		if (selectedBlock == null)
			return;
		PsychUIInputText.focusOn = null;
		selectedStack.blocks.remove(selectedBlock);
		selectedBlock = null;
		dirty = true;
		refreshStackTiles();
		refreshInspector();
	}

	function filterPalette(query:String):Void
	{
		query = query.toLowerCase().trim();
		filtered = palette.filter(def -> (def.name + ' ' + def.category).toLowerCase().contains(query));
		paletteScroll = 0;
		scrollPalette(0);
	}

	function scrollPalette(change:Int):Void
	{
		paletteScroll = clampScroll(paletteScroll + change, filtered.length, paletteTiles.length);
		paletteEmpty.visible = filtered.length == 0;
		paletteUp.alpha = paletteScroll > 0 ? 1 : 0.45;
		paletteDown.alpha = paletteScroll + paletteTiles.length < filtered.length ? 1 : 0.45;
		for (i => tile in paletteTiles)
		{
			var def = filtered[i + paletteScroll];
			tile.visible = def != null;
			if (def != null)
				tile.paint(def.name, blockColor(def.category), false);
		}
	}

	function refreshWorkspace(syncFilter:Bool = true):Void
	{
		for (i => tile in hats)
		{
			var hat = LuaBlocksProject.hats[i];
			var active = project.stacks.exists(stack -> stack.hat == hat.id && stack.blocks.length > 0);
			tile.paint(hat.label + (active ? ' *' : ''), HAT, hat == selectedHat);
		}
		var stacks = project.stacks.filter(stack -> stack.hat == selectedHat.id);
		stackHat.paint(selectedHat.id, HAT, true);
		stackPosition.text = stacks.length == 0 ? '0 / 0' : (stacks.indexOf(selectedStack) + 1) + ' / ' + stacks.length;
		stackUp.exists = stackDown.exists = stacks.length > 1;
		removeStackButton.exists = selectedStack != null;
		filterLabel.visible = filterInput.exists = selectedHat.filterLabel != null;
		filterLabel.text = selectedHat.filterLabel ?? '';
		if (syncFilter)
			filterInput.text = selectedStack == null ? '' : selectedStack.filter;
		refreshStackTiles();
	}

	function refreshStackTiles():Void
	{
		var blocks = selectedStack == null ? [] : selectedStack.blocks;
		stackScroll = clampScroll(stackScroll, blocks.length, stackTiles.length);
		stackEmpty.visible = blocks.length == 0;
		for (i => tile in stackTiles)
		{
			var block = blocks[i + stackScroll];
			tile.visible = block != null;
			if (block == null)
				continue;
			var def = definitions.get(block.id);
			var args = [for (value in block.values) value.source == '' ? value.text : "$" + value.source];
			var details = args.join('  |  ');
			if (details.length > 90)
				details = details.substr(0, 87) + '...';
			tile.paint(def.name + '   ' + details, blockColor(def.category), block == selectedBlock);
		}
	}

	function refreshInspector():Void
	{
		var def = selectedBlock == null ? null : definitions.get(selectedBlock.id);
		inspectTitle.text = def == null ? 'Select a block' : def.name;
		blockDescription.text = def == null ? '' : def.desc ?? '';
		removeBlockButton.exists = def != null;
		var fields = def == null ? [] : LuaBlocksProject.editableFields(def);
		for (i in 0...FIELDS)
		{
			var field = fields[i];
			var active = field != null;
			fieldLabels[i].visible = active;
			fieldInputs[i].exists = sourceButtons[i].exists = fieldPickers[i].exists = false;
			if (!active)
				continue;
			var value = selectedBlock.values[i];
			fieldLabels[i].text = field.label;
			fieldInputs[i].text = value.text;
			fieldInputs[i].exists = value.source == '';
			sourceButtons[i].exists = selectedHat.params.length > 0 && field.type != 'spriteTag';
			sourceButtons[i].label = value.source == '' ? 'Use input' : "$" + value.source;
			fieldPickers[i].exists = value.source == '' && fieldChoices(field).length > 0;
		}
	}

	function fieldChoices(field:BlockFieldDef):Array<String>
	{
		return switch (field.type)
		{
			case 'bool': ['true', 'false'];
			case 'ease': ['linear', 'quadIn', 'quadOut', 'quadInOut', 'cubeIn', 'cubeOut', 'sineIn', 'sineOut', 'sineInOut', 'bounceOut', 'elasticOut'];
			case 'object': ['boyfriend', 'dad', 'gf'].concat(spriteTags());
			case 'spriteTarget': spriteTags();
			default: field.options ?? [];
		};
	}

	function spriteTags():Array<String>
	{
		var tags:Array<String> = [];
		for (stack in project.stacks)
			for (block in stack.blocks)
				if (block.id == 'create_sprite' || block.id == 'add_sprite')
				{
					var tag = block.values[0].text.trim();
					if (tag != '' && !tags.contains(tag))
						tags.push(tag);
				}
		return tags;
	}

	function pickValue(index:Int):Void
	{
		var field = LuaBlocksProject.editableFields(definitions.get(selectedBlock.id))[index];
		var values = fieldChoices(field);
		showChoices(field.label, values, values, value ->
		{
			selectedBlock.values[index].text = value;
			dirty = true;
			refreshInspector();
			refreshStackTiles();
		});
	}

	function pickSource(index:Int):Void
	{
		var sources = [''].concat(selectedHat.params);
		showChoices('Value source', sources, ['Type a value'].concat(selectedHat.params.map(param -> "$" + param)), value ->
		{
			selectedBlock.values[index].source = value;
			dirty = true;
			refreshInspector();
			refreshStackTiles();
		});
	}

	static function blockColor(category:String):Int
	{
		return switch (category)
		{
			case 'Visual': 0xFFA394FF;
			case 'Camera': 0xFF57C8DE;
			case 'Audio': 0xFFF988AC;
			case 'Gameplay': 0xFF82D7AE;
			default: 0xFFFFB479;
		};
	}

	static function clampScroll(scroll:Int, count:Int, visible:Int):Int
		return Std.int(FlxMath.bound(scroll, 0, Math.max(0, count - visible)));

	override function update(elapsed:Float):Void
	{
		var focus = PsychUIInputText.focusOn;
		if (pendingPath != null)
		{
			var path = pendingPath;
			pendingPath = null;
			openDialog = null;
			openScript(path);
		}
		if (browseCancelled)
		{
			browseCancelled = false;
			openDialog = null;
		}
		if (openDialog != null)
			return;

		var escape = FlxG.keys.justPressed.ESCAPE #if android || FlxG.android.justReleased.BACK #end;
		if (escape)
		{
			if (overlayMode != null)
				hideOverlay();
			else if (dragDef != null)
				clearDrag();
			else if (focus != null)
				PsychUIInputText.focusOn = null;
			else
				leave();
			return;
		}
		super.update(elapsed);
		if (subState != null)
			return;
		if (overlayMode != null)
		{
			updateOverlay();
			return;
		}
		if (focus == null)
		{
			if (FlxG.keys.justPressed.DELETE)
				removeBlock();
			if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.S)
			{
				exportScript();
				return;
			}
		}

		var wheel = FlxG.mouse.wheel;
		if (wheel != 0)
		{
			if (FlxG.mouse.x >= MARGIN && FlxG.mouse.x < centerX && FlxG.mouse.y >= PALETTE_Y && FlxG.mouse.y < footerY)
				scrollPalette(-wheel);
			else if (inStack())
				scrollStack(-wheel);
		}
		if (FlxG.mouse.justPressed)
			startDrag();
		if (dragDef != null)
			updateDrag(elapsed);
	}

	function startDrag():Void
	{
		for (i => tile in hats)
			if (tile.hit())
			{
				selectStack(LuaBlocksProject.hats[i]);
				return;
			}
		for (i => tile in paletteTiles)
			if (tile.hit())
			{
				dragDef = filtered[paletteScroll + i];
				break;
			}
		if (dragDef == null)
			for (i => tile in stackTiles)
				if (tile.hit())
				{
					selectedBlock = dragBlock = selectedStack.blocks[stackScroll + i];
					dragDef = definitions.get(dragBlock.id);
					refreshInspector();
					refreshStackTiles();
					break;
				}
		if (dragDef != null)
		{
			dragStartX = FlxG.mouse.x;
			dragStartY = FlxG.mouse.y;
		}
	}

	function updateDrag(elapsed:Float):Void
	{
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;
		if (!dragging && (Math.abs(mx - dragStartX) > 5 || Math.abs(my - dragStartY) > 5))
		{
			dragging = true;
			ghost.paint(dragDef.name, blockColor(dragDef.category), true);
		}
		if (dragging)
		{
			ghost.visible = true;
			ghost.x = FlxMath.bound(mx + 12, 0, FlxG.width - 220);
			ghost.y = FlxMath.bound(my + 12, 0, FlxG.height - ROW);
			insertMark.visible = inStack();
			if (insertMark.visible)
			{
				dragScroll -= elapsed;
				if (dragScroll <= 0)
				{
					if (my < STACK_Y + 12)
						scrollStack(-1);
					else if (my > STACK_Y + stackTiles.length * ROW - 20)
						scrollStack(1);
					dragScroll = 0.10;
				}
				insertMark.x = centerX + 22;
				insertMark.y = STACK_Y + (dropIndex() - stackScroll) * ROW - 2;
			}
		}
		if (FlxG.mouse.justReleased)
		{
			if (!dragging && dragBlock == null)
				dropBlock(selectedHat, stackLength());
			else if (dragging && inStack())
				dropBlock(selectedHat, dropIndex());
			else if (dragging)
				for (i => tile in hats)
					if (tile.hit())
					{
						var hat = LuaBlocksProject.hats[i];
						var target = hat == selectedHat ? selectedStack : project.stacks.find(stack -> stack.hat == hat.id);
						dropBlock(hat, target == null ? 0 : target.blocks.length);
						break;
					}
			clearDrag();
		}
		else if (!FlxG.mouse.pressed)
			clearDrag();
	}

	function inStack():Bool
		return FlxG.mouse.x >= centerX && FlxG.mouse.x < rightX - MARGIN && FlxG.mouse.y >= STACK_Y - 34 && FlxG.mouse.y < footerY - 8;

	function stackLength():Int
		return selectedStack == null ? 0 : selectedStack.blocks.length;

	function dropIndex():Int
	{
		var row = Math.round((FlxG.mouse.y - STACK_Y) / ROW);
		return Std.int(FlxMath.bound(stackScroll + row, stackScroll, Math.min(stackLength(), stackScroll + stackTiles.length)));
	}

	function scrollStack(change:Int):Void
	{
		stackScroll += change;
		refreshStackTiles();
	}

	function dropBlock(hat:LuaBlockHat, index:Int):Void
	{
		var from = dragBlock == null ? null : selectedStack;
		var block = dragBlock ?? LuaBlocksProject.newBlock(dragDef);
		if (block.values.exists(value -> value.source != '' && !hat.params.contains(value.source)))
		{
			showStatus('Switch the bound inputs to typed values before moving this block to ' + hat.id + '.', true);
			return;
		}
		var target = hat == selectedHat ? selectedStack : project.stacks.find(stack -> stack.hat == hat.id);
		if (target != null && target != from && target.blocks.length >= LuaBlocksProject.MAX_BLOCKS)
		{
			showStatus('This stack has reached the block limit.', true);
			return;
		}
		if (target == null && project.stacks.length >= LuaBlocksProject.MAX_STACKS)
		{
			showStatus('This project has reached the stack limit.', true);
			return;
		}
		if (hat != selectedHat)
			selectStack(hat, target);
		if (!ensureStack())
			return;
		if (from != null)
		{
			if (from == selectedStack && from.blocks.indexOf(block) < index)
				index--;
			from.blocks.remove(block);
		}
		selectedStack.blocks.insert(index, block);
		selectedBlock = block;
		stackScroll = Std.int(FlxMath.bound(stackScroll, Math.max(0, index - stackTiles.length + 1), index));
		dirty = true;
		refreshWorkspace();
		refreshInspector();
		showStatus('Drag to insert or reorder. Click a palette block to append it.');
	}

	function clearDrag():Void
	{
		dragDef = null;
		dragBlock = null;
		dragging = ghost.visible = insertMark.visible = false;
		dragScroll = 0;
	}

	function showChoices(title:String, values:Array<String>, labels:Array<String>, action:String->Void):Void
	{
		if (values.length == 0)
			return;
		showOverlay('choice', title, 420, 422);
		choiceValues = values;
		choiceLabels = labels;
		choiceAction = action;
		choiceRows = [];
		var x = Std.int((FlxG.width - 420) / 2);
		var y = Std.int((FlxG.height - 422) / 2);
		button(overlay, x + 316, y + 13, '^', 32, () -> scrollChoices(-1));
		button(overlay, x + 357, y + 13, 'v', 32, () -> scrollChoices(1));
		for (i in 0...10)
			choiceRows.push(button(overlay, x + 22, y + 53 + i * 30, '', 376, () -> choose(i)));
		button(overlay, x + 22, y + 372, 'Cancel', 90, hideOverlay);
		scrollChoices(0);
	}

	function scrollChoices(change:Int):Void
	{
		overlayScroll = clampScroll(overlayScroll + change, choiceLabels.length, choiceRows.length);
		for (i => row in choiceRows)
		{
			var text = choiceLabels[overlayScroll + i];
			row.exists = text != null;
			if (text != null)
				row.label = text;
		}
	}

	function choose(index:Int):Void
	{
		var value = choiceValues[overlayScroll + index];
		var action = choiceAction;
		hideOverlay();
		action(value);
	}

	function showPreview():Void
	{
		try
		{
			previewCode = LuaBlocksCodegen.generate(project, definitions);
			previewLines = previewCode.trim().split('\n');
			var width = FlxG.width - 128;
			var height = FlxG.height - 96;
			showOverlay('preview', 'Generated Lua', width, height);
			previewText = label(overlay, 88, 111, width - 48, '', 14);
			previewText.setFormat(Paths.font('vcr.ttf'), 14, INK);
			previewText.textField.wordWrap = false;
			previewRows = Std.int((height - 124) / 18);
			previewPosition = label(overlay, 88, FlxG.height - 90, 350, '', 13, MUTED);
			button(overlay, FlxG.width - 457, FlxG.height - 92, 'Previous', 76, () -> scrollPreview(-previewRows));
			button(overlay, FlxG.width - 373, FlxG.height - 92, 'Next', 68, () -> scrollPreview(previewRows));
			button(overlay, FlxG.width - 297, FlxG.height - 92, 'Copy code', 106, () -> Clipboard.text = previewCode);
			button(overlay, FlxG.width - 183, FlxG.height - 92, 'Close', 95, hideOverlay);
			scrollPreview(0);
		}
		catch (e:Dynamic)
			showStatus(Std.string(e), true);
	}

	function scrollPreview(change:Int):Void
	{
		overlayScroll = clampScroll(overlayScroll + change, previewLines.length, previewRows);
		var end = Std.int(Math.min(overlayScroll + previewRows, previewLines.length));
		previewText.text = previewLines.slice(overlayScroll, end).join('\n');
		previewPosition.text = 'Lines ' + (overlayScroll + 1) + '-' + end + ' of ' + previewLines.length;
	}

	function showOverlay(mode:String, title:String, width:Int, height:Int):Void
	{
		PsychUIInputText.focusOn = null;
		clearDrag();
		overlayMode = mode;
		overlayScroll = 0;
		ui.active = false;
		var x = (FlxG.width - width) / 2;
		var y = (FlxG.height - height) / 2;
		box(overlay, 0, 0, FlxG.width, FlxG.height, 0xBB090A14);
		box(overlay, x, y, width, height, PANEL);
		label(overlay, x + 22, y + 12, width - 118, title, 20);
	}

	function hideOverlay():Void
	{
		overlay.forEach(member -> member.destroy());
		overlay.clear();
		overlayMode = null;
		choiceRows = [];
		choiceAction = null;
		ui.active = true;
	}

	function updateOverlay():Void
	{
		var wheel = FlxG.mouse.wheel;
		if (overlayMode == 'choice' && wheel != 0)
			scrollChoices(-wheel);
		else if (overlayMode == 'preview')
		{
			if (wheel != 0)
				scrollPreview(-wheel * 3);
			if (FlxG.keys.justPressed.PAGEUP)
				scrollPreview(-previewRows);
			if (FlxG.keys.justPressed.PAGEDOWN)
				scrollPreview(previewRows);
		}
	}

	function refreshDestination():Void
	{
		try
		{
			var path = exportPath();
			var relative = Paths.getModRelativePath(path);
			destination.text = relative == null ? path : 'mods/' + relative;
			destination.color = INK;
		}
		catch (e:Dynamic)
		{
			destination.text = Std.string(e);
			destination.color = 0xFFFFAF9E;
		}
	}

	function exportPath():String
	{
		var name = project.name.trim();
		if (name.toLowerCase().endsWith('.lua'))
			name = name.substr(0, name.length - 4);
		if (!validFilePart(name))
			throw 'Enter a valid script filename.';
		var rawSong = project.song.trim();
		if (rawSong == '')
			return Path.join([modRoot, 'scripts', name + '.lua']);
		var song = Paths.formatToSongPath(rawSong);
		if (!validFilePart(song))
			throw 'Enter a valid song name or folder ID.';
		return Path.join([modRoot, 'data', song, name + '.lua']);
	}

	static function validFilePart(value:String):Bool
	{
		return value != '' && value.length <= 100 && !value.endsWith('.') && !value.endsWith(' ')
			&& !~/[\/\\:*?"<>|\x00-\x1f]/.match(value)
			&& !~/^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.match(value);
	}

	function confirmDiscard(action:Void->Void):Void
	{
		PsychUIInputText.focusOn = null;
		clearDrag();
		if (dirty)
			openSubState(new Prompt('Discard the unsaved changes?', action));
		else
			action();
	}

	function leave():Void
	{
		confirmDiscard(() ->
		{
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			MusicBeatState.switchState(new MasterEditorMenu());
		});
	}

	function browse():Void
	{
		#if desktop
		var dialog = new FileDialog();
		dialog.onSelect.add(onBrowseSelect);
		dialog.onCancel.add(onBrowseCancel);
		openDialog = dialog;
		try
		{
			var folder = modRoot;
			try
			{
				var destination = Path.directory(exportPath());
				if (FileSystem.exists(destination))
					folder = destination;
			}
			catch (_:Dynamic) {}
			dialog.browse(FileDialogType.OPEN, 'lua', folder + '/');
		}
		catch (e:Dynamic)
		{
			openDialog = null;
			showStatus('Could not open the file picker. ' + Std.string(e), true);
		}
		#else
		try openScript(exportPath()) catch (e:Dynamic) showStatus(Std.string(e), true);
		#end
	}

	function onBrowseSelect(path:String):Void
		pendingPath = path;

	function onBrowseCancel():Void
		browseCancelled = true;

	function openScript(path:String):Void
	{
		try
		{
			var code = File.getContent(path);
			var next = LuaBlocksProject.decode(code, definitions);
			var handEdited = LuaBlocksProject.body(code) != LuaBlocksCodegen.generate(next, definitions).trim();
			loadProject(next);
			if (!handEdited)
			{
				savedPath = Path.normalize(FileSystem.absolutePath(path));
				savedContent = code;
			}
			showStatus(handEdited ? 'Loaded the saved blocks. Export will regenerate the Lua and asks before replacing the edited file.'
				: 'Opened ' + Path.withoutDirectory(path), handEdited);
		}
		catch (e:Dynamic)
			showStatus('Could not open Lua. ' + Std.string(e), true);
	}

	function exportScript():Void
	{
		PsychUIInputText.focusOn = null;
		clearDrag();
		try
		{
			if (!project.stacks.exists(stack -> stack.blocks.length > 0))
				throw 'Add at least one block before exporting.';
			var path = Path.normalize(FileSystem.absolutePath(exportPath()));
			var code = project.encode(LuaBlocksCodegen.generate(project, definitions));
			var previous = FileSystem.exists(path) ? File.getContent(path) : null;
			if (previous != null && previous != code && (savedPath != path || savedContent != previous))
				openSubState(new Prompt('Replace the existing Lua?\n' + Path.withoutDirectory(path), () -> writeScript(path, code, previous)));
			else
				writeScript(path, code, previous);
		}
		catch (e:Dynamic)
			showStatus('Could not export Lua. ' + Std.string(e), true);
	}

	function writeScript(path:String, code:String, previous:String):Void
	{
		try
		{
			var current = FileSystem.exists(path) ? File.getContent(path) : null;
			if (current != previous)
				throw 'The destination changed. Export again to review it.';
			if (current != code)
			{
				var folder = Path.directory(path);
				if (!FileSystem.exists(folder))
					FileSystem.createDirectory(folder);
				replaceScript(path, code, current);
			}
			savedPath = path;
			savedContent = code;
			dirty = false;
			showStatus('Exported ' + path);
		}
		catch (e:Dynamic)
			showStatus('Could not export Lua. ' + Std.string(e), true);
	}

	static function replaceScript(path:String, code:String, previous:String):Void
	{
		// Stage the write before moving the old file. Windows cannot always replace an existing file with rename.
		var suffix = '-' + Std.string(Date.now().getTime()) + '-' + Std.random(1000000);
		var temporary = path + suffix + '.tmp';
		var backup = path + suffix + '.bak';
		var backedUp = false;
		try
		{
			File.saveContent(temporary, code);
			var current = FileSystem.exists(path) ? File.getContent(path) : null;
			if (current != previous)
				throw 'The destination changed. Export again to review it.';
			if (current != null)
			{
				FileSystem.rename(path, backup);
				backedUp = true;
			}
			FileSystem.rename(temporary, path);
		}
		catch (e:Dynamic)
		{
			try
			{
				if (FileSystem.exists(temporary))
					FileSystem.deleteFile(temporary);
			}
			catch (_:Dynamic) {}
			if (backedUp)
			{
				if (FileSystem.exists(path))
					throw 'The previous version is available at ' + backup;
				try FileSystem.rename(backup, path) catch (_:Dynamic) throw 'The previous version is available at ' + backup;
			}
			throw e;
		}
		if (backedUp)
			try FileSystem.deleteFile(backup) catch (_:Dynamic) {}
	}

	override function destroy():Void
	{
		PsychUIInputText.focusOn = null;
		FlxG.mouse.visible = false;
		if (openDialog != null)
		{
			openDialog.onSelect.remove(onBrowseSelect);
			openDialog.onCancel.remove(onBrowseCancel);
		}
		super.destroy();
	}
}

private class LuaBlockTile extends FlxSpriteGroup
{
	var backing:FlxSprite;
	var accent:FlxSprite;
	var tab:FlxSprite;
	var caption:FlxText;

	public function new(x:Float, y:Float, width:Int, height:Int, font:String, connected:Bool)
	{
		super(x, y);
		backing = layer(0, 0, width, height);
		accent = layer(0, 0, 5, height);
		if (connected)
			tab = layer(19, height - 1, 22, 5);
		caption = new FlxText(12, 4, width - 20, '', 14);
		caption.setFormat(font, 14, 0xFFF3F1FF);
		caption.textField.wordWrap = false;
		add(caption);
	}

	function layer(x:Int, y:Int, width:Int, height:Int):FlxSprite
	{
		var sprite = new FlxSprite(x, y).makeGraphic(1, 1, FlxColor.WHITE);
		sprite.setGraphicSize(width, height);
		sprite.updateHitbox();
		add(sprite);
		return sprite;
	}

	public function paint(text:String, color:Int, highlight:Bool):Void
	{
		caption.text = text;
		backing.color = highlight ? 0xFF4C4977 : 0xFF2E324C;
		accent.color = color;
		if (tab != null)
			tab.color = color;
	}

	public function hit():Bool
		return visible && FlxG.mouse.overlaps(backing);
}
