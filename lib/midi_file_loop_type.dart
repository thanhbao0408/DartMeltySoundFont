/// Specifies the non-standard loop extension for MIDI files.
enum MidiFileLoopType {
  /// No loop extension is used.
  none,

  /// The RPG Maker style loop is used.
  /// CC #111 corresponds to the loop start point in this case.
  rpgMaker,

  /// The Incredible Machine style loop is used.
  /// CC #110 and #111 respectively correspond to the loop start point and end point in this case.
  incredibleMachine,

  /// The Final Fantasy style loop is used.
  /// CC #116 and #117 respectively correspond to the loop start point and end point in this case.
  finalFantasy
}

MidiFileLoopType midiFileLoopTypeFromInt(int i) {
  switch (i) {
    case 0:
      return MidiFileLoopType.none;
    case 1:
      return MidiFileLoopType.rpgMaker;
    case 2:
      return MidiFileLoopType.incredibleMachine;
    case 3:
      return MidiFileLoopType.finalFantasy;
  }
  throw "invalid midi file loop type";
}

int midiFileLoopTypeToInt(MidiFileLoopType v) {
  switch (v) {
    case MidiFileLoopType.none:
      return 0;
    case MidiFileLoopType.rpgMaker:
      return 1;
    case MidiFileLoopType.incredibleMachine:
      return 2;
    case MidiFileLoopType.finalFantasy:
      return 3;
  }
}
