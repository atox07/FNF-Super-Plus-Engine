package backend;

import backend.WeekData;
import backend.Highscore;
import backend.Song;
import states.FreeplayState;
import states.FreeplayState.SongMetadata;
import states.VSliceFreeplayState;
import openfl.utils.AssetType;

/**
 * API statica, minima, per i menu Freeplay scritti in HScript.
 * Lo script non tocca mai FreeplayState direttamente: passa da qui.
 * Le canzoni sono restituite come oggetti anonimi semplici
 * ({index, name, week, character, color, folder}).
 */
@:keep
class FreeplayAPI
{
	static var songs:Array<SongMetadata> = [];
	static var lastDiffName:String = null;
	static var previewing:Bool = false;

	// ------------------------------------------------------------------
	// Canzoni e difficolta'
	// ------------------------------------------------------------------

	/** Carica le canzoni dalle week (stessa logica del tuo FreeplayState.create). */
	public static function loadSongs():Array<Dynamic>
	{
		songs = [];
		WeekData.reloadWeekFiles(false);

		for (i in 0...WeekData.weeksList.length)
		{
			if (weekIsLocked(WeekData.weeksList[i]))
				continue;

			var leWeek:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			WeekData.setDirectoryFromWeek(leWeek);
			for (song in leWeek.songs)
			{
				if (song[0].toLowerCase().endsWith('-erect'))
					continue;

				var colors:Array<Int> = song[2];
				if (colors == null || colors.length < 3)
					colors = [146, 113, 253];
				songs.push(new SongMetadata(song[0], i, song[1], FlxColor.fromRGB(colors[0], colors[1], colors[2])));
			}
		}
		Mods.loadTopMod();
		WeekData.setDirectoryFromWeek();

		var out:Array<Dynamic> = [];
		for (i in 0...songs.length)
		{
			var s:SongMetadata = songs[i];
			out.push({
				index: i,
				name: s.songName,
				week: s.week,
				character: s.songCharacter,
				color: s.color,
				folder: s.folder
			});
		}
		return out;
	}

	static function weekIsLocked(name:String):Bool
	{
		var leWeek:WeekData = WeekData.weeksLoaded.get(name);
		return (!leWeek.startUnlocked
			&& leWeek.weekBefore.length > 0
			&& (!StoryMenuState.weekCompleted.exists(leWeek.weekBefore) || !StoryMenuState.weekCompleted.get(leWeek.weekBefore)));
	}

	/** Seleziona una canzone (imposta mod/week) e restituisce i nomi grezzi delle difficolta'. */
	public static function selectSong(index:Int):Array<String>
	{
		var s:SongMetadata = songs[index];
		Mods.currentModDirectory = s.folder;
		PlayState.storyWeek = s.week;

		Difficulty.loadFromWeek();
		if (Difficulty.list == null || Difficulty.list.length == 0)
			Difficulty.list = ['Normal'];
		return Difficulty.list.copy();
	}

	/** Nome tradotto della difficolta' i (dopo selectSong). */
	public static function difficultyLabel(i:Int):String
		return Difficulty.getString(i);

	/** Indice della difficolta' ricordata (o di default) per la lista corrente. */
	public static function defaultDifficulty():Int
	{
		var wanted:String = lastDiffName != null ? lastDiffName : Difficulty.getDefault();
		var idx:Int = Difficulty.list.indexOf(wanted);
		return idx < 0 ? 0 : idx;
	}

	public static function rememberDifficulty(i:Int):Void
	{
		if (i >= 0 && i < Difficulty.list.length)
			lastDiffName = Difficulty.list[i];
	}

	// ------------------------------------------------------------------
	// Punteggi
	// ------------------------------------------------------------------
	public static function getScore(index:Int, diff:Int):Int
		return Highscore.getScore(songs[index].songName, diff, FreeplayState.viewingOpponentScores);

	public static function getRating(index:Int, diff:Int):Float
		return Highscore.getRating(songs[index].songName, diff, FreeplayState.viewingOpponentScores);

	// ------------------------------------------------------------------
	// Audio
	// ------------------------------------------------------------------
	public static function ensureMenuMusic():Void
	{
		if (previewing || FlxG.sound.music == null || !FlxG.sound.music.playing)
		{
			FlxG.sound.playMusic(Paths.music('freakyMenu'), 0.7, true);
			previewing = false;
		}
		Conductor.bpm = 102;
	}

	public static function playPreview(index:Int, diff:Int):Void
	{
		try
		{
			var key:String = Paths.formatToSongPath(songs[index].songName);
			var snd = Paths.inst(key);
			if (snd == null)
				return;

			FlxG.sound.playMusic(snd, 0, true);
			FlxG.sound.music.fadeIn(0.8, 0, 0.7);
			previewing = true;

			try
			{
				var chart:SwagSong = Song.getChart(Highscore.formatSong(key, diff), key);
				Conductor.bpm = (chart != null && chart.bpm > 0) ? chart.bpm : 102;
			}
			catch (e:Dynamic)
				Conductor.bpm = 102;
		}
		catch (e:Dynamic)
			trace('[FreeplayAPI] preview fallita: $e');
	}

	// ------------------------------------------------------------------
	// Navigazione
	// ------------------------------------------------------------------

	/** Avvia la canzone. Restituisce null se ok, altrimenti il messaggio d'errore. */
	public static function startSong(index:Int, diff:Int):String
	{
		var song:SongMetadata = songs[index];
		Mods.currentModDirectory = song.folder;

		var songLowercase:String = Paths.formatToSongPath(song.songName);
		var poop:String = Highscore.formatSong(songLowercase, diff);

		try
		{
			Song.loadFromJson(poop, songLowercase);
			if (PlayState.SONG == null)
				throw 'Chart failed to load: $poop';
		}
		catch (e:haxe.Exception)
		{
			trace('ERROR! ${e.message}');
			var msg:String = e.message;
			if (msg.contains('There is no TEXT asset with an ID of')
				|| msg.contains('Invalid difficulty index')
				|| msg.contains('chart file not found'))
				msg = 'No chart is available for this difficulty!';
			return msg;
		}

		@:privateAccess
		if (PlayState._lastLoadedModDirectory != Mods.currentModDirectory)
		{
			trace('CHANGED MOD DIRECTORY, RELOADING STUFF');
			Paths.freeGraphicsFromMemory();
		}

		savedSelection = index;
		LoadingState.prepareToSong();
		LoadingState.returnState = backend.ScriptableState.tryCreate('VSliceFreeplayState', new VSliceFreeplayState());
		LoadingState.loadAndSwitchState(new PlayState());
		#if !SHOW_LOADING_SCREEN
		FlxG.sound.music.stop();
		#end
		FreeplayState.destroyFreeplayVocals();
		#if (MODS_ALLOWED && DISCORD_ALLOWED)
		DiscordClient.loadModRPC();
		#end
		return null;
	}

	/** Indice (nella lista completa) salvato dal Freeplay classico o dall'ultima uscita. */
	public static var savedSelection(get, set):Int;

	static function get_savedSelection():Int
		return FreeplayState.curSelected;

	static function set_savedSelection(v:Int):Int
	{
		FreeplayState.curSelected = v;
		return v;
	}

	public static function goClassic(index:Int):Void
	{
		leave(index);
		MusicBeatState.switchState(new FreeplayState());
	}

	public static function goMainMenu(index:Int):Void
	{
		leave(index);
		MusicBeatState.switchState(backend.ScriptableState.tryCreate('MainMenuState', new states.MainMenuState()));
	}

	static function leave(index:Int):Void
	{
		if (index >= 0)
			savedSelection = index;
		ensureMenuMusic();
	}

	// ------------------------------------------------------------------
	// Utility asset (evitano di esporre AssetType a HScript)
	// ------------------------------------------------------------------
	public static function imageExists(key:String):Bool
		return Paths.fileExists('images/$key.png', AssetType.IMAGE);

	public static function atlasExists(key:String):Bool
		return imageExists(key) && Paths.fileExists('images/$key.xml', AssetType.TEXT);

	public static function soundExists(key:String):Bool
		return Paths.fileExists('sounds/$key.${Paths.SOUND_EXT}', AssetType.SOUND);

	public static function playSfx(key:String, volume:Float = 1):Void
	{
		if (soundExists(key))
			FlxG.sound.play(Paths.sound(key), volume);
	}
}
