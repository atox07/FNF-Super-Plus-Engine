package backend.ui;

import backend.ui.PsychUIBox.UIStyleData;

/**
 * Dropdown riutilizzabile per gli editor (Event Creator, Dialogue, ecc.).
 * Funziona come un <select>: click sul campo -> apre lista -> click su opzione.
 * Emette CHANGE_EVENT quando il valore cambia (intercettato da PsychUIEvent).
 *
 * Uso:
 *   var dd = new PsychUIDropDown(10, 10, 150, ['bf', 'dad', 'gf'], 'bf', function(v) trace('scelto: $v'));
 *   tab.add(dd);
 */
class PsychUIDropDown extends FlxSpriteGroup {
	public static final CHANGE_EVENT = 'dropdown_change';
	public static final OPEN_EVENT   = 'dropdown_open';
	public static final CLOSE_EVENT  = 'dropdown_close';

	/** Quante opzioni mostrare prima di attivare lo scroll interno */
	public static final MAX_VISIBLE:Int = 8;
	public static final OPTION_HEIGHT:Int = 18;

	public var label(default, set):String;
	public var bg:FlxSprite;
	public var text:FlxText;
	public var arrow:FlxText;

	public var onChange:String->Void = null;
	public var broadcastEvent:Bool = true;

	/** Lista aperta (creata solo quando serve) */
	var _listGroup:FlxSpriteGroup = null;
	var _listBg:FlxSprite = null;
	var _optionTexts:Array<FlxText> = [];
	var _optionBgs:Array<FlxSprite> = [];
	var _isOpen:Bool = false;
	var _scrollIndex:Int = 0;

	/** Opzioni correnti */
	public var options(default, set):Array<String> = [];
	/** Valore corrente. '' = placeholder */
	public var value(default, set):String = '';

	// Stili coerenti con PsychUIButton
	public var normalStyle:UIStyleData = {
		bgColor: 0xFFAAAAAA,
		textColor: FlxColor.BLACK,
		bgAlpha: 1
	};
	public var hoverStyle:UIStyleData = {
		bgColor: FlxColor.WHITE,
		textColor: FlxColor.BLACK,
		bgAlpha: 1
	};
	public var openStyle:UIStyleData = {
		bgColor: FlxColor.BLACK,
		textColor: FlxColor.WHITE,
		bgAlpha: 1
	};

	var _fieldWidth:Int = 150;
	var _firstFrame:Bool = true;
	var _forceCheckNext:Bool = true;

	public function new(x:Float = 0, y:Float = 0, width:Int = 150, ?options:Array<String> = null, ?defaultValue:String = '', ?onChange:String->Void = null) {
		super(x, y);
		_fieldWidth = width;

		bg = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		bg.color = 0xFFAAAAAA;
		bg.alpha = 1;
		add(bg);

		text = new FlxText(4, 0, width - 22, '');
		text.setFormat(null, 8, FlxColor.BLACK, LEFT);
		add(text);

		arrow = new FlxText(width - 16, 0, 14, '▼');
		arrow.setFormat(null, 8, FlxColor.BLACK, CENTER);
		add(arrow);

		resize(width, OPTION_HEIGHT);

		this.options = (options != null) ? options : [];
		this.value = defaultValue;
		this.onChange = onChange;

		_flistSetup();
	}

	// ------------------------------------------------------------------
	// Resize
	// ------------------------------------------------------------------
	public function resize(width:Int, height:Int) {
		_fieldWidth = width;
		bg.setGraphicSize(width, height);
		bg.updateHitbox();
		text.fieldWidth = width - 22;
		text.y = (height - text.height) / 2;
		arrow.y = (height - arrow.height) / 2;
		arrow.x = width - 16;
		if (_listBg != null && _listBg.exists) {
			_listBg.setGraphicSize(width, 1);
			_listBg.updateHitbox();
		}
	}

	// ------------------------------------------------------------------
	// Lista (creata lazy al primo open)
	// ------------------------------------------------------------------
	function _flistSetup():Void {
		_listGroup = new FlxSpriteGroup();
		_listGroup.visible = false;
		_listGroup.active = false;
		add(_listGroup);

		_listBg = new FlxSprite().makeGraphic(_fieldWidth, 1, FlxColor.WHITE);
		_listBg.color = 0xFF222222;
		_listBg.alpha = 0.95;
		_listGroup.add(_listBg);
	}

	function _rebuildList():Void {
		// Pulisci opzioni precedenti
		for (t in _optionTexts) _listGroup.remove(t, true);
		for (b in _optionBgs)  _listGroup.remove(b, true);
		_optionTexts = [];
		_optionBgs = [];

		var visibleCount = Std.int(Math.min(options.length, MAX_VISIBLE));
		var listHeight = visibleCount * OPTION_HEIGHT;
		_listBg.setGraphicSize(_fieldWidth, listHeight);
		_listBg.updateHitbox();

		for (i in 0...options.length) {
			var ob = new FlxSprite(0, i * OPTION_HEIGHT).makeGraphic(_fieldWidth, OPTION_HEIGHT, FlxColor.BLACK);
			ob.alpha = 0.001;
			_listGroup.add(ob);
			_optionBgs.push(ob);

			var ot = new FlxText(4, i * OPTION_HEIGHT + 3, _fieldWidth - 8, options[i]);
			ot.setFormat(null, 8, FlxColor.WHITE, LEFT);
			_listGroup.add(ot);
			_optionTexts.push(ot);
		}
		_applyScroll();
	}

	function _applyScroll():Void {
		var maxScroll = Std.int(Math.max(0, options.length - MAX_VISIBLE));
		_scrollIndex = Std.int(Math.max(0, Math.min(_scrollIndex, maxScroll)));
		var offset = -_scrollIndex * OPTION_HEIGHT;
		for (i in 0..._optionTexts.length) {
			_optionTexts[i].y = i * OPTION_HEIGHT + 3 + offset;
			_optionBgs[i].y = i * OPTION_HEIGHT + offset;
			var visible = (i >= _scrollIndex && i < _scrollIndex + MAX_VISIBLE);
			_optionTexts[i].visible = visible;
			_optionBgs[i].visible = visible;
		}
	}

	// ------------------------------------------------------------------
	// Open / close
	// ------------------------------------------------------------------
	function _open():Void {
		if (_isOpen) return;
		_isOpen = true;
		_rebuildList();
		_listGroup.visible = true;
		_listGroup.active = true;
		bg.color = openStyle.bgColor;
		bg.alpha = openStyle.bgAlpha;
		text.color = openStyle.textColor;
		arrow.text = '▲';
		if (broadcastEvent)
			PsychUIEventHandler.event(OPEN_EVENT, this);
	}

	function _close():Void {
		if (!_isOpen) return;
		_isOpen = false;
		_listGroup.visible = false;
		_listGroup.active = false;
		bg.color = normalStyle.bgColor;
		bg.alpha = normalStyle.bgAlpha;
		text.color = normalStyle.textColor;
		arrow.text = '▼';
		if (broadcastEvent)
			PsychUIEventHandler.event(CLOSE_EVENT, this);
	}

	// ------------------------------------------------------------------
	// Update
	// ------------------------------------------------------------------
	override function update(elapsed:Float):Void {
		super.update(elapsed);

		if (_firstFrame) {
			bg.color = normalStyle.bgColor;
			bg.alpha = normalStyle.bgAlpha;
			text.color = normalStyle.textColor;
			_firstFrame = false;
		}

		// Hover + click sul campo
		var overField = FlxG.mouse.overlaps(bg, camera);
		if (!_isOpen && overField) {
			bg.color = hoverStyle.bgColor;
			bg.alpha = hoverStyle.bgAlpha;
			text.color = hoverStyle.textColor;
		} else if (!_isOpen && !overField) {
			bg.color = normalStyle.bgColor;
			bg.alpha = normalStyle.bgAlpha;
			text.color = normalStyle.textColor;
		}

		if (FlxG.mouse.justPressed) {
			if (!_isOpen && overField) {
				_open();
				return;
			}

			if (_isOpen) {
				// Click dentro la lista
				var clickedOption = -1;
				for (i in 0..._optionBgs.length) {
					if (!_optionBgs[i].visible) continue;
					if (FlxG.mouse.overlaps(_optionBgs[i], camera)) {
						clickedOption = i;
						break;
					}
				}
				if (clickedOption >= 0) {
					_selectOption(clickedOption);
					return;
				}
				// Click fuori dalla lista e fuori dal campo -> chiudi
				if (!overField) {
					_close();
					return;
				}
			}
		}

		// Scroll interno quando aperto
		if (_isOpen && FlxG.mouse.wheel != 0) {
			var insideList = false;
			for (i in 0..._optionBgs.length) {
				if (_optionBgs[i].visible && FlxG.mouse.overlaps(_optionBgs[i], camera)) {
					insideList = true;
					break;
				}
			}
			if (insideList || overField) {
				_scrollIndex -= FlxG.mouse.wheel;
				_applyScroll();
			}
		}

		// Esc chiude
		if (_isOpen && FlxG.keys.justPressed.ESCAPE)
			_close();
	}

	function _selectOption(i:Int):Void {
		if (i < 0 || i >= options.length) return;
		value = options[i];
		_close();
		if (onChange != null)
			onChange(value);
		if (broadcastEvent)
			PsychUIEventHandler.event(CHANGE_EVENT, this);
	}

	// ------------------------------------------------------------------
	// Set / get
	// ------------------------------------------------------------------
	function set_value(v:String):String {
		value = (v == null) ? '' : v;
		if (value == '') {
			text.text = '(nessuno)';
			text.color = 0xFF666666;
		} else {
			text.text = value;
			if (!_isOpen) text.color = normalStyle.textColor;
		}
		return value;
	}

	function set_options(v:Array<String>):Array<String> {
		options = (v != null) ? v : [];
		if (_isOpen) _rebuildList();
		return options;
	}

	function set_label(v:String):String {
		// label è solo per chiarezza; il testo mostrato è il value
		return (label = v);
	}

	public function isOpen():Bool return _isOpen;

	override function destroy():Void {
		_optionTexts = null;
		_optionBgs = null;
		_listGroup = null;
		_listBg = null;
		super.destroy();
	}
}
