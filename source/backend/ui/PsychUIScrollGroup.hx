package backend.ui;

/**
 * Contenitore scrollabile per widget PsychUI.
 * - Intercetta la rotellina quando il mouse e' sopra il viewport
 * - Muove i figli verticalmente
 * - Nasconde i figli fuori dal viewport (e li disattiva)
 * - Scrollbar visiva sul bordo destro
 *
 * Uso tipico:
 *   var scroll = new PsychUIScrollGroup(10, 10, 300, 200);
 *   tab.add(scroll);
 *   scroll.addItem(card1, 80);   // altezza esplicita o -1 per auto
 *   scroll.addItem(card2, 120);
 *   scroll.refresh();
 */
class PsychUIScrollGroup extends FlxSpriteGroup {
	public var content(default, null):FlxSpriteGroup;
	public var viewportWidth(default, null):Float;
	public var viewportHeight(default, null):Float;

	/** Pixel scrollati per tacca di rotellina */
	public var scrollSpeed:Float = 30;
	/** Se true, mostra una scrollbar sul bordo destro */
	public var showScrollbar:Bool = true;

	var _scrollY:Float = 0;
	var _maxScroll:Float = 0;
	var _items:Array<FlxBasic> = [];
	var _heights:Map<FlxBasic, Float> = new Map();

	var _viewportBg:FlxSprite;      // hit-test del mouse
	var _scrollbarBg:FlxSprite;     // traccia
	var _scrollbarThumb:FlxSprite;  // cursore

	public function new(x:Float = 0, y:Float = 0, width:Float = 200, height:Float = 200) {
		super(x, y);
		viewportWidth = width;
		viewportHeight = height;

		// Sfondo invisibile usato per l'hit-test (alpha 0.001 per non vederlo ma restare cliccabile)
		_viewportBg = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		_viewportBg.setGraphicSize(Std.int(width), Std.int(height));
		_viewportBg.updateHitbox();
		_viewportBg.alpha = 0.001;
		add(_viewportBg);

		// Gruppo che contiene i contenuti scrollabili
		content = new FlxSpriteGroup();
		add(content);

		// Scrollbar
		_scrollbarBg = new FlxSprite(width - 6).makeGraphic(4, Std.int(height), 0xFF333333);
		_scrollbarBg.alpha = 0.5;
		add(_scrollbarBg);

		_scrollbarThumb = new FlxSprite(width - 6).makeGraphic(4, 20, 0xFF888888);
		_scrollbarThumb.alpha = 0.9;
		add(_scrollbarThumb);

		_updateScrollbar();
	}

	// ----------------------------------------------------------------
	// API pubblica
	// ----------------------------------------------------------------

	/**
	 * Aggiunge un item scrollabile.
	 * itemHeight: altezza usata per il range di scroll.
	 *             Se < 0, prova a usare .height del item (se FlxSprite), altrimenti 20.
	 */
	public function addItem(item:FlxBasic, itemHeight:Float = -1):Void {
		if (item == null) return;

		var h:Float = itemHeight;
		if (h < 0) {
			if (Std.isOfType(item, FlxSprite)) h = cast(item, FlxSprite).height;
			else h = 20;
		}

		content.add(item);
		_items.push(item);
		_heights.set(item, h);
		refresh();
	}

	public function removeItem(item:FlxBasic):Void {
		if (item == null) return;
		content.remove(item, true);
		_items.remove(item);
		_heights.remove(item);
		refresh();
	}

	public function clearItems():Void {
		for (it in _items) content.remove(it, true);
		_items = [];
		_heights = new Map();
		refresh();
	}

	/**
	 * Ricalcola l'altezza totale e clampa lo scroll.
	 * Chiamala dopo aver aggiunto/modificato item o cambiato le loro y.
	 */
	public function refresh():Void {
		var totalHeight:Float = 0;
		for (item in _items) {
			var h = _heights.get(item);
			if (h == null) h = 20;
			var bottom = item.y + h;
			if (bottom > totalHeight) totalHeight = bottom;
		}
		_maxScroll = Math.max(0, totalHeight - viewportHeight);
		_scrollY = Math.max(0, Math.min(_scrollY, _maxScroll));
		_applyScroll();
	}

	/** Scrolla di un delta (positivo = giu') */
	public function scrollBy(delta:Float):Void {
		_scrollY = Math.max(0, Math.min(_scrollY + delta, _maxScroll));
		_applyScroll();
	}

	/** Porta lo scroll a un valore assoluto */
	public function setScroll(v:Float):Void {
		_scrollY = Math.max(0, Math.min(v, _maxScroll));
		_applyScroll();
	}

	public function getScroll():Float return _scrollY;
	public function getMaxScroll():Float return _maxScroll;

	// ----------------------------------------------------------------
	// Update: rotellina
	// ----------------------------------------------------------------
	override function update(elapsed:Float):Void {
		super.update(elapsed);

		if (_maxScroll <= 0) return;

		if (FlxG.mouse.overlaps(_viewportBg, camera) && FlxG.mouse.wheel != 0) {
			scrollBy(-FlxG.mouse.wheel * scrollSpeed);
		}
	}

	// ----------------------------------------------------------------
	// Interni
	// ----------------------------------------------------------------
	function _applyScroll():Void {
		content.y = -_scrollY;

		// Visibilita' manuale degli item fuori dal viewport
		var top = _scrollY;
		var bottom = _scrollY + viewportHeight;
		for (item in _items) {
			var h = _heights.get(item);
			if (h == null) h = 20;
			var iy = item.y;
			var vis = (iy + h > top && iy < bottom);
			item.visible = vis;
			item.active = vis;
		}

		_updateScrollbar();
	}

	function _updateScrollbar():Void {
		var visible = showScrollbar && _maxScroll > 0;
		_scrollbarBg.visible = visible;
		_scrollbarThumb.visible = visible;
		if (!visible) return;

		var ratio = viewportHeight / (viewportHeight + _maxScroll);
		var thumbH = Math.max(20, viewportHeight * ratio);
		_scrollbarThumb.setGraphicSize(4, Std.int(thumbH));
		_scrollbarThumb.updateHitbox();

		var trackH = viewportHeight - thumbH;
		var scrollRatio = (_maxScroll > 0) ? (_scrollY / _maxScroll) : 0;
		_scrollbarThumb.y = scrollRatio * trackH;
	}

	override function destroy():Void {
		_items = null;
		_heights = null;
		content = null;
		_scrollbarBg = null;
		_scrollbarThumb = null;
		_viewportBg = null;
		super.destroy();
	}
}
