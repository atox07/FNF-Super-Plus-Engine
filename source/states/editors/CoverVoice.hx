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
		var buf=AudioBuffer.fromFile(path);
		if(buf==null || buf.data==null || buf.bitsPerSample!=16) throw "Expected decoded 16-bit PCM WAV/OGG";
		var b=buf.data.toBytes(), c=buf.channels;
		var pcm=[for(i in 0...Std.int(b.length/(2*c))) {
			var v=0.;
			for(j in 0...c) {var k=(i*c+j)*2; var x=b.get(k)|(b.get(k+1)<<8); v+=(x>=32768?x-65536:x)/32768.;}
			v/c;
		}];
		if (pcm.length == 0 || buf.sampleRate <= 0) throw "Empty or invalid audio file";
		samples=pcm; rate=buf.sampleRate; source=path;
		if (manual) resetMarkers(); else slice();
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
	public function render(seconds:Float):Bytes {
		var frames=Math.ceil(seconds*RATE);
		var mix=new haxe.ds.Vector<Float>(frames);
		for(i in 0...frames)mix[i]=0.;
		if(!muted && slices.length>0) for(n in notes) {
			var idx=Std.int(Math.max(0,Math.min(slices.length-1,n.pitch-root)));
			var s=slices[idx], pos:Float=s.a;
			var begin=Math.round((offset+n.start)*RATE), length=Math.round(n.duration*RATE);
			var step=rate/RATE*Math.pow(2,(n.pitch-root-idx)/12);
			var accel=Math.pow(2,n.slide/(12.*Math.max(1,length)));
			for(j in 0...length) {
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
		for(i in 0...frames)b.setUInt16(i*2,Std.int(Math.max(-1,Math.min(1,mix[i]))*32767)&65535);
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
			pcm.setUInt16(frame * 2, Std.int(value * 32767) & 65535);
		}
		return pcm;
	}

	/** Anteprima di una singola nota (per sentirla mentre la sposti nel piano roll). */
	public function preview(n:CoverNote):Bytes {
		var oldNotes=notes, oldOffset=offset, oldMuted=muted;
		var dur=Math.min(0.8,Math.max(0.15,n.duration));
		notes=[{start:0.,duration:dur,pitch:n.pitch,velocity:n.velocity,channel:n.channel,slide:n.slide}];
		offset=0; muted=false;
		var b=render(dur+0.05);
		notes=oldNotes; offset=oldOffset; muted=oldMuted;
		return b;
	}
}
#end
