package states.editors;

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

	public function new() {}
	public function load(path:String) {
		var buf=AudioBuffer.fromFile(path);
		if(buf==null || buf.data==null || buf.bitsPerSample!=16) throw "Expected decoded 16-bit PCM WAV/OGG";
		var b=buf.data.toBytes(), c=buf.channels;
		var pcm=[for(i in 0...Std.int(b.length/(2*c))) {
			var v=0.;
			for(j in 0...c) {var k=(i*c+j)*2; var x=b.get(k)|(b.get(k+1)<<8); v+=(x>=32768?x-65536:x)/32768.;}
			v/c;
		}];
		samples=pcm; rate=buf.sampleRate; source=path; slice();
	}
	public function slice() {
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
}
