package states.editors;

#if sys

import states.editors.CoverMidi.CoverNote;
import haxe.io.Bytes;
import lime.media.AudioBuffer;
import openfl.media.Sound;

class CoverVoice {
	public static inline var RATE = 44100;
	public var root = 48;
	public var threshold = 0.015;
	public var source = "";
	public var offset = 0.;
	public var muted = false;
	public var gain:Float = 1.0;
	public var notes:Array<CoverNote> = [];
	var samples:Array<Float> = [];
	var rate = RATE;
	var slices:Array<{a:Int,b:Int}> = [];

	/** Transient detection sensitivity 0..1 (higher = more slices). */
	public var sensitivity = 0.5;
	/** How the slices were made: 'silence', 'transient' or 'manual'. */
	public var mode = 'silence';

	public function new() {}
	public function load(path:String, manual:Bool = false) {
		var decoded = haxe.io.Path.extension(path).toLowerCase() == "wav"
			? decodeWav(sys.io.File.getBytes(path)) : null;
		if (decoded == null) {
			var buf = AudioBuffer.fromFile(path);
			if (buf == null || buf.data == null || buf.bitsPerSample != 16 || buf.channels < 1 || buf.sampleRate < 1)
				throw "Unsupported or invalid audio file";
			var bytes = buf.data.toBytes();
			decoded = {
				pcm: readFrames(bytes, 0, bytes.length, buf.channels, 2, 1),
				rate: buf.sampleRate
			};
		}
		if (decoded.pcm.length == 0) throw "Empty audio file";
		samples = decoded.pcm;
		rate = decoded.rate;
		source = path;
		if (manual) resetMarkers(); else slice();
	}

	// Non-PCM WAV codecs are passed to the existing Lime decoder.
	static function decodeWav(b:Bytes):Null<{pcm:Array<Float>, rate:Int}> {
		if (b.length < 12 || b.getString(0, 4) != "RIFF" || b.getString(8, 4) != "WAVE") return null;
		var size = b.getInt32(4);
		if (size < 4 || size > b.length - 8) throw "Invalid WAV length";
		var end = size + 8;
		var pos = 12;
		var fmt = -1, fmtSize = 0, data = -1, dataSize = 0;
		while (end - pos >= 8) {
			var tag = b.getString(pos, 4);
			var length = b.getInt32(pos + 4);
			pos += 8;
			if (length < 0 || length > end - pos) throw "Truncated WAV chunk";
			if (tag == "fmt " && fmt < 0) { fmt = pos; fmtSize = length; }
			if (tag == "data" && data < 0) { data = pos; dataSize = length; }
			pos += length;
			if (pos < end) pos += length & 1;
		}
		if (fmtSize < 16 || data < 0) throw "Missing WAV format or audio data";
		var format = b.getUInt16(fmt);
		var channels = b.getUInt16(fmt + 2);
		var hz = b.getInt32(fmt + 4);
		var align = b.getUInt16(fmt + 12);
		var bits = b.getUInt16(fmt + 14);
		if (format == 0xfffe) {
			if (fmtSize < 40 || b.getUInt16(fmt + 16) < 22) throw "Invalid extensible WAV format";
			// KSDATAFORMAT_SUBTYPE_PCM / IEEE_FLOAT share the final 12 GUID bytes.
			if (b.getInt32(fmt + 28) != 0x00100000 || b.getInt32(fmt + 32) != 0xaa000080
				|| b.getInt32(fmt + 36) != 0x719b3800) return null;
			format = b.getInt32(fmt + 24);
		}
		if (format != 1 && format != 3) return null;
		if (format == 1 && bits != 8 && bits != 16 && bits != 24 && bits != 32)
			throw "Unsupported PCM bit depth: " + bits;
		if (format == 3 && bits != 32 && bits != 64) throw "Unsupported float bit depth: " + bits;
		var width = bits >> 3;
		if (channels < 1 || hz < 1 || align != channels * width || dataSize % align != 0)
			throw "Invalid WAV frame layout";
		return {pcm: readFrames(b, data, dataSize, channels, width, format), rate: hz};
	}

	static function readFrames(b:Bytes, pos:Int, length:Int, channels:Int, width:Int, format:Int):Array<Float> {
		var pcm:Array<Float> = [];
		var end = pos + length;
		while (pos < end) {
			var sum = 0.0;
			for (c in 0...channels) {
				var value:Float;
				if (format == 3) {
					value = width == 8 ? b.getDouble(pos) : b.getFloat(pos);
					if (!Math.isFinite(value)) value = 0;
				} else {
					value = switch (width) {
						case 1: (b.get(pos) - 128) / 128.0;
						case 2: (b.getUInt16(pos) << 16 >> 16) / 32768.0;
						case 3: ((b.getUInt16(pos) << 8 | b.get(pos + 2) << 24) >> 8) / 8388608.0;
						default: b.getInt32(pos) / 2147483648.0;
					};
				}
				sum += value / channels;
				pos += width;
			}
			pcm.push(sum);
		}
		return pcm;
	}

	public function resetMarkers() {
		slices = [];
		if (samples.length > 0) slices.push({a:0, b:samples.length});
		mode = 'manual';
	}
	public function slice() {
		mode='silence';
		slices=[];
		var first=-1,last=-1;
		for(i in 0...samples.length) {
			if(Math.abs(samples[i])>=threshold) {if(first<0) first=i; last=i;}
			else if(first>=0 && i-last>rate*.035) {slices.push({a:first,b:last+1}); first=-1;}
		}
		if(first>=0)slices.push({a:first,b:last+1});
	}
	// In polyphonic passages a target belongs to the most recently started
	// sustained note on its MIDI channel. Equal starts use the higher pitch.
	public function sourceAt(time:Float, channel:Int = -1):CoverNote {
		var source:CoverNote = null;
		for (n in notes) {
			if (n.slideTarget == true || (channel >= 0 && n.channel != channel)) continue;
			if (n.start <= time && time < n.start + n.duration &&
				(source == null || n.start > source.start || (n.start == source.start && n.pitch > source.pitch)))
				source = n;
		}
		return source;
	}

	public function render(seconds:Float):Bytes
		return renderWindow(seconds, offset, null, false);

	function renderWindow(seconds:Float, timeOffset:Float, solo:CoverNote, audition:Bool):Bytes {
		var frames=Math.ceil(seconds*RATE);
		var mix=new haxe.ds.Vector<Float>(frames);
		for(i in 0...frames)mix[i]=0.;
		var targets = new haxe.ds.ObjectMap<CoverNote, Array<CoverNote>>();
		for (target in notes) {
			if (target.slideTarget != true || target.duration <= 0) continue;
			var source = sourceAt(target.start, target.channel);
			if (source == null || (solo != null && solo != source)) continue;
			if (!targets.exists(source)) targets.set(source, []);
			targets.get(source).push(target);
		}
		if((audition || !muted) && slices.length>0) for(n in notes) {
			if (n.slideTarget == true || (solo != null && n != solo)) continue;
			var idx=Std.int(Math.max(0,Math.min(slices.length-1,n.pitch-root)));
			var s=slices[idx], pos:Float=s.a;
			var begin=Math.round((timeOffset+n.start)*RATE), length=Math.round(n.duration*RATE);
			var step=rate/RATE*Math.pow(2,(n.pitch-root-idx)/12);
			var accel=Math.pow(2,n.slide/(12.*Math.max(1,length)));
			var baseStep = step;
			var slides = targets.get(n);
			if (slides != null) slides.sort(function(a,b) return Reflect.compare(a.start,b.start));
			var index = 0;
			var nextStart = slides == null ? length : Math.round((slides[0].start - n.start) * RATE);
			var glideEnd = -1;
			var goal = step;
			for(j in 0...length) {
				if (j == glideEnd) { step = goal; accel = 1; }
				while (slides != null && index < slides.length && j >= nextStart) {
					var target = slides[index++];
					var span = Std.int(Math.max(1, Math.round(target.duration * RATE)));
					goal = baseStep * Math.pow(2, (target.pitch - n.pitch) / 12.0);
					accel = Math.pow(goal / step, 1.0 / span);
					glideEnd = j + span;
					nextStart = index < slides.length ? Math.round((slides[index].start - n.start) * RATE) : length;
				}
				var out=begin+j;
				if(out>=frames)break;
				var k=Std.int(pos), next=k+1<s.b?k+1:s.a;
				var fade=Math.min(1,Math.min(j,length-1-j)/128.);
				if(out>=0)mix[out]+=(samples[k]+(samples[next]-samples[k])*(pos-k))*n.velocity/127.*fade;
				pos=s.a+(pos-s.a+step)%(s.b-s.a);
				step*=accel;
			}
		}
		var b=Bytes.alloc(frames*2);
		for(i in 0...frames)b.setUInt16(i*2,Std.int(Math.max(-1,Math.min(1,mix[i] * gain))*32767)&65535);
		return b;
	}
	public static function wav(b:Bytes):Bytes {
		var w=new haxe.io.BytesOutput();
		w.bigEndian=false;
		w.writeString("RIFF"); w.writeInt32(36+b.length); w.writeString("WAVEfmt "); w.writeInt32(16);
		w.writeUInt16(1);w.writeUInt16(1);w.writeInt32(RATE);w.writeInt32(RATE*2);w.writeUInt16(2);w.writeUInt16(16);
		w.writeString("data");w.writeInt32(b.length);w.write(b);return w.getBytes();
	}

	public function sliceCount():Int
		return slices.length;

	public function sampleCount():Int
		return samples.length;

	public function sampleRate():Int
		return rate;

	public function getSlice(i:Int):{a:Int,b:Int}
		return slices[i];

	/** Slices as plain arrays [a,b] (for saving projects). */
	public function slicesAsArray():Array<Array<Int>>
		return [for(s in slices) [s.a, s.b]];

	public function setSlices(a:Array<Array<Int>>) {
		slices=[for(x in a) {a:x[0], b:x[1]}];
		slices.sort(function(p, q) return p.a-q.a);
		mode='manual';
	}

	/** Re-run the automatic slicing mode that is currently active. */
	public function resliceAuto() {
		if(mode=='transient') detectTransients(); else if(mode=='silence') slice();
	}

	/** SliceX-style detection: a new slice starts at every energy onset. Slices are contiguous. */
	public function detectTransients() {
		mode='transient';
		slices=[];
		var win=512, hop=256, n=Std.int(samples.length/hop);
		if(n<2) { if(samples.length>0) slices.push({a:0,b:samples.length}); return; }
		var env:Array<Float>=[];
		for(k in 0...n) {
			var st=k*hop, en=Std.int(Math.min(samples.length,st+win)), e=0.;
			for(i in st...en) e+=samples[i]*samples[i];
			env.push(Math.sqrt(e/Math.max(1,en-st)));
		}
		var ratio=1.2+(1-sensitivity)*4;
		var minGap=Std.int(rate*.04/hop)+1;
		var onsets:Array<Int>=[0];
		var lastK=0;
		for(k in 1...n) {
			var prev=0., c=0;
			for(j in Std.int(Math.max(0,k-6))...k) {prev+=env[j]; c++;}
			prev/=Math.max(1,c);
			if(env[k]>=threshold && env[k]>prev*ratio+0.0005 && k-lastK>=minGap) {onsets.push(k*hop); lastK=k;}
		}
		for(i in 0...onsets.length) {
			var end = i+1 < onsets.length ? onsets[i+1] : samples.length;
			slices.push({a:onsets[i], b:end});
		}
	}

	/** Index of the slice that contains sample x, or -1. */
	public function sliceAt(x:Int):Int {
		var lo = 0;
		var hi = slices.length - 1;
		while (lo <= hi) {
			var mid = (lo + hi) >>> 1;
			var region = slices[mid];
			if (x < region.a) hi = mid - 1;
			else if (x >= region.b) lo = mid + 1;
			else return mid;
		}
		return -1;
	}

	/** Cut at sample x (inside a slice) or create a slice there (in a gap). Returns the new slice index or -1. */
	public function splitAt(x:Int):Int {
		x=Std.int(Math.max(0,Math.min(samples.length-1,x)));
		var i=sliceAt(x);
		if(i>=0) {
			var s=slices[i];
			if(x-s.a<64 || s.b-x<64) return -1;
			mode='manual';
			slices.insert(i+1,{a:x, b:s.b});
			s.b=x;
			return i+1;
		}
		var at=0;
		while(at<slices.length && slices[at].a<x) at++;
		var end=at<slices.length?slices[at].a:samples.length;
		if(end-x<64) return -1;
		mode='manual';
		slices.insert(at,{a:x, b:end});
		return at;
	}

	public function removeSlice(i:Int) {
		if(i>=0 && i<slices.length) {slices.splice(i,1); mode='manual';}
	}

	/** Merge slice i with the following one. */
	public function mergeNext(i:Int) {
		if(i>=0 && i+1<slices.length) {slices[i].b=slices[i+1].b; slices.splice(i+1,1); mode='manual';}
	}

	public function clearSlices() {
		slices=[];
		mode='manual';
	}

	/** Move the left or right edge of slice i. A shared (contiguous) edge moves both neighbours together. */
	public function setEdge(i:Int, left:Bool, x:Int) {
		if(i<0 || i>=slices.length) return;
		mode='manual';
		var s=slices[i];
		if(left) {
			var prev=i>0?slices[i-1]:null;
			var joined=prev!=null && prev.b==s.a;
			var lo=prev==null?0:(joined?prev.a+1:prev.b);
			var v=Std.int(Math.max(lo,Math.min(s.b-1,x)));
			s.a=v;
			if(joined) prev.b=v;
		} else {
			var next=i+1<slices.length?slices[i+1]:null;
			var joined=next!=null && next.a==s.b;
			var hi=next==null?samples.length:(joined?next.b-1:next.a);
			var v=Std.int(Math.min(hi,Math.max(s.a+1,x)));
			s.b=v;
			if(joined) next.a=v;
		}
	}

	/** Waveform peaks for the visible range: [min0,max0,min1,max1,...], one pair per column. */
	public function waveform(start:Float, span:Float, cols:Int):Array<Float> {
		var out:Array<Float>=[];
		for(c in 0...cols) {
			var s0=Std.int(start+c*span/cols), s1=Std.int(start+(c+1)*span/cols);
			if(s0<0) s0=0;
			if(s1>samples.length) s1=samples.length;
			if(s0>=samples.length || s1<=s0) {out.push(0); out.push(0); continue;}
			var mn=0., mx=0., stride=Std.int(Math.max(1,(s1-s0)/24));
			var i=s0;
			while(i<s1) {
				var v=samples[i];
				if(v<mn) mn=v;
				if(v>mx) mx=v;
				i+=stride;
			}
			out.push(mn); out.push(mx);
		}
		return out;
	}

	/** Audio of slice i played once (for previewing it in the slicer). */
	public function previewSlice(i:Int):Bytes {
		var s = slices[i];
		var frames = Math.ceil((s.b - s.a) * (RATE / rate));
		var pcm = Bytes.alloc(frames * 2);
		for (frame in 0...frames) {
			var pos = Math.min(s.b - 1, s.a + frame * (rate / RATE));
			var k = Std.int(pos);
			var next = k + 1 < s.b ? k + 1 : k;
			var value = samples[k] + (samples[next] - samples[k]) * (pos - k);
			pcm.setUInt16(frame * 2, Std.int(Math.max(-1, Math.min(1, value * gain)) * 32767) & 65535);
		}
		return pcm;
	}

	/** Anteprima di una singola nota (per sentirla mentre la sposti nel piano roll). */
	public function preview(n:CoverNote):Bytes {
		var source = n.slideTarget == true ? sourceAt(n.start, n.channel) : n;
		if (source == null) return Bytes.alloc(2);
		var start = Math.max(source.start, n.start - 0.06);
		var duration = Math.min(1.2, Math.min(source.start + source.duration, n.start + n.duration + 0.08) - start);
		return renderWindow(Math.max(0.01, duration), -start, source, true);
	}
}
#end
