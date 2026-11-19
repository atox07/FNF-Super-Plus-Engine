package states.editors.luablocks;

import states.editors.eventcreator.EventDef.BlockDef;
import states.editors.eventcreator.EventPalette;

class LuaBlocksPalette
{
	public static function load():Array<BlockDef>
	{
		EventPalette.load(false);
		var sprite = EventPalette.get('add_sprite');
		if (sprite == null)
			throw EventPalette.loadError ?? 'The sprite blocks are missing.';

		var spriteFields = sprite.fields.copy();
		spriteFields[0] = {key: 'sprite', label: 'Sprite tag', type: 'spriteTag', def: 'mySprite'};
		var blocks:Array<BlockDef> = [
			{id: 'create_sprite', name: 'Create Sprite', category: 'Visual', desc: 'Load an image from the images folder under a sprite tag.',
				fields: spriteFields.slice(0, 4), template: "makeLuaSprite($sprite, $image, $x, $y)"},
			{id: 'place_sprite', name: 'Add Sprite to Scene', category: 'Visual', desc: 'Show a sprite created by a Create Sprite block.',
				fields: [{key: 'sprite', label: 'Sprite tag', type: 'spriteTarget', def: 'mySprite'}, spriteFields[4]],
				template: "addLuaSprite($sprite, $front)"},
			{id: 'add_sprite', name: 'Create + Add Sprite', category: 'Visual', desc: sprite.desc, fields: spriteFields, template: sprite.template},
		];
		for (id in [
			'set_property', 'set_visible', 'play_animation', 'tween_x', 'tween_y', 'tween_alpha', 'tween_angle', 'tween_color',
			'camera_shake', 'camera_flash', 'play_sound', 'set_health', 'add_health', 'trigger_event'
		])
		{
			var def = EventPalette.get(id);
			if (def != null)
				blocks.push(def);
		}
		blocks.push({
			id: 'run_timer', name: 'Start Timer', category: 'Other', desc: 'Start a named timer. It fires On timer when each loop finishes.',
			fields: [
				{key: 'timer', label: 'Timer tag', type: 'timerTag', def: 'myTimer'},
				{key: 'seconds', label: 'Seconds', type: 'float', def: '1'},
				{key: 'loops', label: 'Loops (0 = repeat)', type: 'int', def: '1'}
			],
			template: "runTimer($timer, math.max(0.001, $seconds), math.max(0, $loops))"
		});
		for (id in ['wait', 'debug_print'])
		{
			var def = EventPalette.get(id);
			if (def != null)
				blocks.push(def);
		}
		return blocks;
	}
}
