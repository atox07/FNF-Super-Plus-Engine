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

class CoverMidi {
	public static function read(bytes:Bytes, ?onInitialTempo:Float->Void):Array<CoverNote> {
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
						var on = active.get(key).shift();
						raw.push({a:on.tick,b:tick,p:a,v:on.v,c:ch});
					}
				}
			}
		}
		for (event in tempo) if (event.us <= 0) throw "Invalid MIDI tempo";
		tempo.sort((a,b)->a.tick == b.tick ? a.order-b.order : a.tick-b.tick);
		if (onInitialTempo != null) {
			var initialUs = 500000;
			for (event in tempo) {
				if (event.tick != 0) break;
				initialUs = event.us;
			}
			onInitialTempo(60000000.0 / initialUs);
		}
		function seconds(t:Int):Float {
			var last=0, us=500000, sum=0.;
			for (e in tempo) {
				if(e.tick>t) break;
				sum+=(e.tick-last)*(us/1000000.0)/division;
				last=e.tick; us=e.us;
			}
			return sum+(t-last)*(us/1000000.0)/division;
		}
		return [for (n in raw) {start:seconds(n.a),duration:seconds(n.b)-seconds(n.a),pitch:n.p,velocity:n.v,channel:n.c,slide:0}];
	}
	static function variable(r:BytesInput):Int {
		var n=0;
		for(i in 0...4) {var b=r.readByte(); n=(n<<7)|(b&127); if(b<128)return n;}
		throw "Invalid MIDI delta";
	}
}
