package states.editors;

import backend.Paths;
import flixel.FlxG;
import flixel.FlxSubState;
import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.media.Sound;
import openfl.media.SoundChannel;
import lime.media.AudioBuffer;
import lime.ui.FileDialog;
import lime.ui.FileDialogType;
import haxe.io.Bytes;
import sys.io.File;
import sys.FileSystem;
import states.editors.CoverMidi.CoverNote;

class CoverMaker extends FlxSubState {
	var panel=new Sprite();
	var lane=new Sprite();
	var status=new TextField();
	var voices=[new CoverVoice(),new CoverVoice()];
	var active=0;
	var inst:Sound;
	var instPath="";
	var song:String;
	var bpm:Float;
	var cursor=0.;
	var origin=0.;
	var playing=false;
	var started=0.;
	var startedAt=0.;
	var channels:Array<SoundChannel>=[];
	var secondsPerPage=8.;
	var page=0.;
	var low=48;
	var selected:CoverNote;
	var drag="";
	var dx=0.;
	var dy=0.;
	var old=0.;
	var oldPitch=0;
	var dialog:FileDialog;
	var catalog:Array<String>=[];
	var songIndex=-1;
	var grid:Float;
	var stageRef:openfl.display.Stage;
	public function new(song:String,bpm:Float) {
		super();this.song=song;this.bpm=bpm;grid=60/Math.max(1,bpm)/4;
	}
	override public function create() {
		super.create();
		stageRef=FlxG.stage;
		stageRef.addChild(panel);
		panel.graphics.beginFill(0x161924);panel.graphics.drawRect(0,0,1000,580);panel.graphics.endFill();
		panel.addChild(lane);
		status.defaultTextFormat=new TextFormat("_sans",14,0xffffff);
		status.width=980;status.height=40;status.x=10;status.y=540;panel.addChild(status);
		try {inst=Paths.inst(song);} catch(e:Dynamic) {info(Std.string(e));}
		button(0,0,"Inst file",()->pick("ogg,wav",p->{var s=Sound.fromFile(p);if(s==null)throw "Audio load failed";inst=s;instPath=p;refresh();info(p);}));
		button(1,0,"Songs >",()->{
			if(catalog.length==0)scanSongs();
			if(catalog.length==0)throw "No instrumental found in assets/songs or mods";
			var p=catalog[++songIndex%catalog.length];var s=Sound.fromFile(p);if(s==null)throw "Audio load failed";
			inst=s;instPath=p;refresh();info(p);
		});
		button(2,0,"Dad MIDI",()->midi(0));button(3,0,"BF MIDI",()->midi(1));
		button(4,0,"Dad voice",()->chrom(0));button(5,0,"BF voice",()->chrom(1));
		button(6,0,"Save",()->project(true));button(7,0,"Open",()->project(false));
		button(0,1,"Play / Pause",()->{if(playing)halt();else {origin=cursor;play();}});
		button(1,1,"Stop",()->{halt();cursor=origin;draw();});
		button(2,1,"Page <",()->{page=Math.max(0,page-secondsPerPage);draw();});
		button(3,1,"Page >",()->{page+=secondsPerPage;draw();});
		button(4,1,"Octave -",()->{low=Std.int(Math.max(0,low-12));draw();});
		button(5,1,"Octave +",()->{low=Std.int(Math.min(104,low+12));draw();});
		button(6,1,"Export stems",()->exportAudio(true));button(7,1,"Export mix",()->exportAudio(false));
		button(0,2,"Root -",()->setting(-1));button(1,2,"Root +",()->setting(1));
		button(2,2,"Threshold -",()->threshold(-.005));button(3,2,"Threshold +",()->threshold(.005));
		button(4,2,"Slide -",()->slide(-1));button(5,2,"Slide +",()->slide(1));
		button(6,2,"Mute track",()->{var v=voices[active];v.muted=!v.muted;refresh();});
		button(7,2,"Close",()->close());
		lane.addEventListener(MouseEvent.MOUSE_DOWN,down);
		stageRef.addEventListener(MouseEvent.MOUSE_UP,up);
		stageRef.addEventListener(KeyboardEvent.KEY_DOWN,key);
		info("Select Dad/BF lane. Drag lane to move pattern. Piano roll: click to add, drag to move, drag right edge to resize, Delete to remove.");
		draw();layout();
	}
	function scanSongs() {
		var roots=["assets/songs","mods/songs"];
		if(FileSystem.exists("mods"))for(m in FileSystem.readDirectory("mods"))roots.push("mods/"+m+"/songs");
		for(r in roots)if(FileSystem.exists(r)&&FileSystem.isDirectory(r))for(s in FileSystem.readDirectory(r)){
			for (ext in ["wav", "ogg"]) {
				var p = r + "/" + s + "/Inst." + ext;
				if (FileSystem.exists(p)) catalog.push(p);
			}
		}
		catalog.sort(Reflect.compare);
	}
	function info(s:String)status.text=s;
	function button(col:Int,row:Int,title:String,fn:Void->Void){
		var b=new Sprite();b.x=6+col*124;b.y=5+row*32;b.graphics.beginFill(0x36445e);b.graphics.drawRoundRect(0,0,118,28,6);b.graphics.endFill();
		var t=new TextField();t.defaultTextFormat=new TextFormat("_sans",14,0xffffff);t.text=title;t.x=5;t.y=3;t.width=113;t.height=23;t.mouseEnabled=false;b.addChild(t);
		panel.addChild(b);b.buttonMode=true;b.addEventListener(MouseEvent.CLICK,(_)->{try fn() catch(e:Dynamic)info(Std.string(e));});
	}
	function pick(filter:String,fn:String->Void,mode:FileDialogType=OPEN){
		dialog=new FileDialog();dialog.onSelect.add(p->{try fn(p) catch(e:Dynamic)info(Std.string(e));});dialog.browse(mode,filter);
	}
	function choose(i:Int){active=i;selected=null;}
	function midi(i:Int)pick("mid,midi",p->{var ns=CoverMidi.read(File.getBytes(p));choose(i);voices[i].notes=ns;if(ns.length>0)low=Std.int(Math.min(104,Math.max(0,ns[0].pitch-8)));refresh();info(ns.length+" notes");});
	function chrom(i:Int)pick("wav,ogg",p->{voices[i].load(p);choose(i);refresh();info(p);});
	function setting(d:Int){var v=voices[active];v.root=Std.int(Math.max(0,Math.min(127,v.root+d)));refresh();info("First slice MIDI pitch "+v.root);}
	function threshold(d:Float){var v=voices[active];v.threshold=Math.max(.001,Math.min(.95,v.threshold+d));v.slice();refresh();info("Slice threshold "+v.threshold);}
	function slide(d:Int){if(selected!=null){selected.slide+=d;refresh();info("Slide "+selected.slide+" semitones over note");}}
	function layout(){panel.scaleX=stageRef.stageWidth/1000.;panel.scaleY=stageRef.stageHeight/580.;}
	function length(){var end=inst==null?0.:inst.length/1000.;for(v in voices)for(n in v.notes)end=Math.max(end,v.offset+n.start+n.duration);return Math.max(.1,end);}
	function halt(){if(playing)cursor=startedAt+haxe.Timer.stamp()-started;playing=false;for(c in channels)if(c!=null)c.stop();channels=[];}
	function play(){
		halt();var end=length();if(cursor>=end)cursor=0;
		var sounds:Array<Sound>=[];
		for(v in voices)if(!v.muted && v.source!="" && v.notes.length>0){
			var buf=AudioBuffer.fromBytes(CoverVoice.wav(v.render(end)));if(buf==null)throw "Preview decode failed";sounds.push(Sound.fromAudioBuffer(buf));
		}
		if(inst!=null)sounds.push(inst);
		for(s in sounds)if(cursor*1000<s.length)channels.push(s.play(cursor*1000));
		startedAt=cursor;started=haxe.Timer.stamp();playing=true;
	}
	function refresh(){if(playing){halt();play();}draw();}
	function rect(x:Float,y:Float,w:Float,h:Float,color:Int){if(w<=0)return;var g=lane.graphics;g.beginFill(color);g.drawRect(x,y,w,h);g.endFill();}
	function label(x:Int,y:Int,s:String){var t=new TextField();t.defaultTextFormat=new TextFormat("_sans",13,0xffffff);t.text=s;t.width=95;t.height=24;t.x=x;t.y=y;t.mouseEnabled=false;lane.addChild(t);}
	function xx(t:Float)return 100+(t-page)*900/secondsPerPage;
	function draw(){
		lane.graphics.clear();while(lane.numChildren>0)lane.removeChildAt(0);
		rect(0,104,1000,430,0x202635);label(4,108,"Time");label(4,137,"Inst");
		rect(100,136,Math.min(900,Math.max(0,xx(inst==null?0.:inst.length/1000.)-100)),22,0x467b86);
		for(i in 0...2){var y=164+i*28;var v=voices[i];label(4,y,(i==0?"Dad":"BF")+(v.muted?" [mute]":""));rect(100,y,900,25,active==i?0x45516a:0x30394c);
			for(n in v.notes){var x=xx(n.start+v.offset);var right=xx(n.start+v.offset+n.duration);rect(Math.max(100,x),y+8,Math.min(1000,right)-Math.max(100,x),8,i==0?0xc391ef:0x68d6cb);}
		}
		for(i in 0...24){var y=224+i*12;var p=low+23-i;rect(100,y,900,11,[1,3,6,8,10].indexOf(p%12)>=0?0x242c3d:0x323c50);if(p%12==0)label(5,y-3,"MIDI "+p);}
		for(i in 0...9){var x=100+i*112.5;rect(x,108,1,404,0x506078);if(i<8)label(Std.int(x)+2,106,Std.string(page+i)+"s");}
		var v=voices[active];
		for(n in v.notes)if(n.pitch>=low && n.pitch<low+24){var x=xx(v.offset+n.start),r=xx(v.offset+n.start+n.duration);rect(Math.max(100,x),224+(low+23-n.pitch)*12,Math.min(1000,r)-Math.max(100,x),11,n==selected?0xffca66:0x65bbac);}
		var x=xx(cursor);if(x>=100&&x<=1000)rect(x,108,2,404,0xffffff);
	}
	function snap(t:Float)return Math.round(t/grid)*grid;
	function down(e:MouseEvent){
		var x=panel.mouseX,y=panel.mouseY,t=page+(x-100)*secondsPerPage/900;dx=x;dy=y;
		if(y<136 && x>=100){var resume=playing;halt();cursor=Math.max(0,t);origin=cursor;if(resume)play();}
		else if(y>=164 && y<220){choose(y<192?0:1);drag="pattern";old=voices[active].offset;}
		else if(y>=224&&y<512&&x>=100){
			var v=voices[active],p=low+23-Std.int((y-224)/12);selected=null;
			for(n in v.notes)if(n.pitch==p && t>=v.offset+n.start && t<=v.offset+n.start+n.duration)selected=n;
			if(selected==null){selected={start:Math.max(0,snap(t-v.offset)),pitch:p,duration:grid,velocity:100,channel:0,slide:0};v.notes.push(selected);drag="new";}
			else {drag=xx(v.offset+selected.start+selected.duration)-x<7?"resize":"move";}
			old=drag=="resize"?selected.duration:selected.start;oldPitch=p;
		}
		draw();
	}
	function move(){var d=snap((panel.mouseX-dx)*secondsPerPage/900);
		switch(drag){
			case "pattern":voices[active].offset=Math.max(0,old+d);
			case "resize":selected.duration=Math.max(grid,old+d);
			case "new","move":selected.start=Math.max(0,old+d);selected.pitch=Std.int(Math.max(0,Math.min(127,oldPitch-Math.round((panel.mouseY-dy)/12))));
			default:
		}
	}
	function up(e:MouseEvent){if(drag!=""){move();drag="";refresh();}}
	function key(e:KeyboardEvent){try {if(e.keyCode==46&&selected!=null){voices[active].notes.remove(selected);selected=null;drag="";refresh();}if(e.keyCode==32){if(playing)halt();else play();}}catch(err:Dynamic)info(Std.string(err));}
	override public function update(elapsed:Float){super.update(elapsed);layout();if(drag!="")move();if(playing){cursor=startedAt+haxe.Timer.stamp()-started;if(cursor>=length())halt();}if(playing||drag!="")draw();}
	function project(save:Bool){
		if(save)pick("json",p->{File.saveContent(p,haxe.Json.stringify({song:song,inst:instPath,tracks:[for(v in voices){root:v.root,threshold:v.threshold,offset:v.offset,path:v.source,notes:v.notes,muted:v.muted}]}));info("Project saved");},SAVE);
		else pick("json",p->{var data:Dynamic=haxe.Json.parse(File.getContent(p));var vs=[];var tracks:Array<Dynamic>=data.tracks;if(tracks.length!=2)throw "Expected two tracks";
			for(t in tracks){var v=new CoverVoice();v.root=t.root;v.threshold=t.threshold;if(t.path!="")v.load(t.path);v.offset=t.offset;v.notes=t.notes;v.muted=t.muted;vs.push(v);}
			var sound=data.inst==""?Paths.inst(data.song):Sound.fromFile(data.inst);halt();voices=vs;inst=sound;song=data.song;instPath=data.inst;cursor=page=0;choose(0);draw();info("Project opened");});
	}
	function exportAudio(split:Bool)pick("",dir->{
		var end=length(),a=voices[0].render(end),b=voices[1].render(end);
		if(split){writeWav(dir+"/Voices-Opponent.wav",a);writeWav(dir+"/Voices-Player.wav",b);}
		else {for(i in 0...Std.int(a.length/2)){var j=i*2,x=a.getUInt16(j),y=b.getUInt16(j);var sum=(x>=32768?x-65536:x)+(y>=32768?y-65536:y);a.setUInt16(j,Std.int(Math.max(-32768,Math.min(32767,sum)))&65535);}writeWav(dir+"/Voices.wav",a);}
		info("Exported to "+dir);
	},OPEN_DIRECTORY);
	function writeWav(path:String, pcm:Bytes){
		File.saveBytes(path, CoverVoice.wav(pcm));
	}
	override public function destroy(){halt();if(stageRef!=null){stageRef.removeEventListener(MouseEvent.MOUSE_UP,up);stageRef.removeEventListener(KeyboardEvent.KEY_DOWN,key);}if(panel.parent!=null)panel.parent.removeChild(panel);super.destroy();}
}
