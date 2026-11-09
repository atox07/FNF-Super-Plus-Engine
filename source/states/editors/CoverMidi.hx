package states.editors;

import haxe.io.Bytes;
import haxe.io.BytesInput;

typedef CoverNote = {
	var start:Float;
	var duration:Float;
	var pitch:Int;
	var velocity:Int;
	var channel:Int;
	var slide:Int; // Legacy relative glide
	@:optional var slideTarget:Bool;
}

typedef TempoPoint = { var step:Float; var bpm:Float; }

class CoverTempo {
	public var points(default,null):Array<TempoPoint>;
	var times:Array<Float> = [];

	public function new(entries:Array<TempoPoint>) {
		if (entries == null || entries.length == 0 || entries[0].step != 0) throw "Missing initial tempo";
		points = [];
		var time = 0.0;
		for (p in entries) {
			if (!Math.isFinite(p.step) || !Math.isFinite(p.bpm) || p.bpm <= 0) throw "Invalid tempo change";
			if (points.length > 0) {
				var prev = points[points.length-1];
				if (p.step <= prev.step) throw "Tempo changes out of order";
				time += (p.step-prev.step) * 15 / prev.bpm;
			}
			points.push({step:p.step,bpm:p.bpm});
			times.push(time);
		}
	}

	function index(value:Float, byTime:Bool):Int {
		var lo = 0, hi = points.length;
		while (lo + 1 < hi) {
			var mid = (lo + hi) >>> 1;
			if ((byTime ? times[mid] : points[mid].step) <= value) lo = mid;
			else hi = mid;
		}
		return lo;
	}

	public function at(time:Float):Int return index(time,true);

	public function stepAt(time:Float):Float {
		var i = at(time);
		return points[i].step + (time-times[i])*points[i].bpm/15;
	}

	public function timeAt(step:Float):Float {
		var i = index(step,false);
		return times[i] + (step-points[i].step)*15/points[i].bpm;
	}

	public function stepLength(time:Float):Float return timeAt(stepAt(time)+1)-time;
}

class CoverMidi {
	public static function read(bytes:Bytes, ?onInitialTempo:Float->Void, autoSlides:Bool = true, ?onMap:CoverTempo->Void, ?fallback:CoverTempo):Array<CoverNote> {
		var f = new BytesInput(bytes);
		f.bigEndian = true;
		if (f.readString(4) != "MThd") throw "Missing MIDI header";
		var size = f.readInt32();
		var format = f.readUInt16(), count = f.readUInt16(), division = f.readUInt16();
		if (size < 6 || size > bytes.length-8 || format > 1 || division == 0 || division >= 32768) throw "Expected format 0/1 MIDI with musical ticks";
		f.position = 8 + size;
		var tempo = [{tick:0, us:500000, order:0}];
		var raw = [];
		var order = 0;
		for (track in 0...count) {
			if (f.readString(4) != "MTrk") throw "Missing MIDI track";
			var len = f.readInt32();
			if (len < 0 || len > bytes.length - f.position) throw "Invalid track length";
			var r = new BytesInput(f.read(len));
			var tick = 0, running = 0;
			var active = new Map<Int,Array<{tick:Int,v:Int}>>();
			while (r.position < r.length) {
				tick += variable(r);
				var op = r.readByte();
				if (op < 128) {r.position--; op = running;}
				if (op < 128) throw "Invalid MIDI running status";
				if (op == 255) {
					var meta = r.readByte(), n = variable(r);
					var b = r.read(n);
					if (meta == 81 && n == 3) tempo.push({tick:tick, us:(b.get(0)<<16)|(b.get(1)<<8)|b.get(2), order:++order});
					running = 0;
				} else if (op == 240 || op == 247) { r.read(variable(r)); running = 0; }
				else {
					if (op >= 240) throw "Invalid MIDI event";
					running = op;
					var kind = op >> 4, ch = op & 15;
					var a = r.readByte(), v = kind == 12 || kind == 13 ? 0 : r.readByte();
					if (a > 127 || v > 127) throw "Invalid MIDI data";
					var key = ch*128+a;
					if (kind == 9 && v > 0) {
						if (!active.exists(key)) active.set(key,[]);
						active.get(key).push({tick:tick,v:v});
					} else if ((kind == 8 || kind == 9) && active.exists(key) && active.get(key).length > 0) {
						var on = active.get(key).pop(); // LIFO: a note nested inside a same-pitch note closes first
						raw.push({a:on.tick,b:tick,p:a,v:on.v,c:ch});
					}
				}
			}
		}
		for (event in tempo) if (event.us <= 0) throw "Invalid MIDI tempo";
		tempo.sort((a,b)->a.tick == b.tick ? a.order-b.order : a.tick-b.tick);
		var entries:Array<TempoPoint> = [];
		for (e in tempo) {
			var step = e.tick * 4.0 / division;
			var bpm = 60000000.0 / e.us;
			if (entries.length > 0 && entries[entries.length-1].step == step)
				entries[entries.length-1].bpm = bpm;
			else entries.push({step:step,bpm:bpm});
		}
		var map = order == 0 && fallback != null ? fallback : new CoverTempo(entries);
		if (onInitialTempo != null) onInitialTempo(map.points[0].bpm);
		if (onMap != null) onMap(map);
		function seconds(t:Int):Float return map.timeAt(t * 4.0 / division);
		var out:Array<CoverNote> = [for (n in raw) {start:seconds(n.a),duration:seconds(n.b)-seconds(n.a),pitch:n.p,velocity:n.v,channel:n.c,slide:0}];
		if (autoSlides) detectSlides(out);
		return out;
	}

	// FL Studio slide notes arrive in the MIDI as plain notes lying on top of a longer
	// note of the same channel. Those become slideTarget notes.
	//  - normal: the note is inside the source and clearly shorter (maxRatio)
	//  - tiny:   very short notes (<= tinyMax s, FL's minimum is even zero-length) only need to
	//            START inside the source, even if they overhang its end
	//  - same pitch: a shorter note nested in a held note is a slide back to that key.
	static function findSlideSource(all:Array<CoverNote>, n:CoverNote, maxRatio:Float, tinyMax:Float, eps:Float):CoverNote {
		var source:CoverNote = null;
		for (s in all) {
			if (s == n || s.channel != n.channel || s.slideTarget == true) continue;
			var end = s.start + s.duration;
			var inside = s.start <= n.start + eps && n.start < end;
			var shorter = s.pitch == n.pitch ? n.duration < s.duration : n.duration < s.duration * maxRatio;
			var contained = inside && n.start + n.duration <= end + eps && shorter;
			var tiny = inside && n.duration <= tinyMax && n.duration < s.duration - 0.0001;
			if ((contained || tiny) && (source == null || s.start > source.start)) source = s;
		}
		return source;
	}

	public static function detectSlides(notes:Array<CoverNote>, maxRatio:Float = 0.7, tinyMax:Float = 0.06, eps:Float = 0.005):Void {
		var sorted = notes.copy();
		sorted.sort((a, b) -> Reflect.compare(b.duration, a.duration)); // longest first
		for (n in sorted) {
			if (n.slideTarget == true) continue;
			if (findSlideSource(sorted, n, maxRatio, tinyMax, eps) == null) continue;
			n.slideTarget = true;
			if (n.duration < 0.005) n.duration = 0.005;
		}
	}

	static function variable(r:BytesInput):Int {
		var n=0;
		for(i in 0...4) {var b=r.readByte(); n=(n<<7)|(b&127); if(b<128)return n;}
		throw "Invalid MIDI delta";
	}
}
