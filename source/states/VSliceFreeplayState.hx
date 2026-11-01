package states;

/**
 * Stub compilato. Il vero menu e' scritto in HScript
 * (scripts/menus/VSliceFreeplayState/init.hx) e viene caricato da
 * ScriptableState.tryCreate('VSliceFreeplayState', new VSliceFreeplayState()).
 *
 * Se lo script non esiste (o non viene trovato) si arriva qui:
 * si torna semplicemente al Freeplay classico.
 */
class VSliceFreeplayState extends MusicBeatState
{
	override function create()
	{
		super.create();
		trace('[VSliceFreeplay] script non trovato: scripts/menus/VSliceFreeplayState/init.hx. Torno al Freeplay classico.');
		persistentUpdate = false;
		MusicBeatState.switchState(new FreeplayState());
	}
}
