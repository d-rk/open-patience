import '../../core/game_state.dart';
import '../../core/move.dart';
import '../../core/pile.dart';

/// Every kind of moment that makes a sound. GameBloc decides *which*
/// moment happened; `SoundBoard` decides what it sounds like.
enum SoundCue { place, foundation, draw, flip, illegal, undo, deal, win }

/// The cue for [move], already applied to [state].
SoundCue cueForMove(Move move, GameState state) {
  if (state.pileAt(move.toPile).kind == PileKind.foundation) {
    return SoundCue.foundation;
  }
  if (move.flipMovedCards) {
    return SoundCue.draw;
  }
  return SoundCue.place;
}
