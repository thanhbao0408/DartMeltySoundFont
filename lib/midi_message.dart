import 'midi_file_loop_type.dart';

class MidiMessageType {
  static const int normal = 0;
  static const int tempoChange = 252;
  static const int loopStart = 253;
  static const int loopEnd = 254;
  static const int endOfTrack = 255;
}

class MidiMessage {
  int channel;
  int command;
  int data1;
  int data2;

  MidiMessage(
      int this.channel, int this.command, int this.data1, int this.data2);

  factory MidiMessage.common1(int status, int data1) {
    int channel = (status & 0x0F);
    int command = (status & 0xF0);
    int data2 = 0;
    return MidiMessage(channel, command, data1, data2);
  }

  factory MidiMessage.common2(
      int status, int data1, int data2, MidiFileLoopType loopType) {
    int channel = (status & 0x0F);
    int command = (status & 0xF0);

    if (command == 0xB0) {
      switch (loopType) {
        case MidiFileLoopType.rpgMaker:
          if (data1 == 111) {
            return loopStart();
          }
          break;

        case MidiFileLoopType.incredibleMachine:
          if (data1 == 110) {
            return loopStart();
          }
          if (data1 == 111) {
            return loopEnd();
          }
          break;

        case MidiFileLoopType.finalFantasy:
          if (data1 == 116) {
            return loopStart();
          }
          if (data1 == 117) {
            return loopEnd();
          }
          break;
        default:
      }
    }

    return MidiMessage(channel, command, data1, data2);
  }

  static MidiMessage tempoChange(int tempo) {
    int command = (tempo >> 16);
    int data1 = (tempo >> 8);
    int data2 = tempo;
    return new MidiMessage(MidiMessageType.tempoChange, command, data1, data2);
  }

  static MidiMessage loopStart() {
    return new MidiMessage(MidiMessageType.loopStart, 0, 0, 0);
  }

  static MidiMessage loopEnd() {
    return new MidiMessage(MidiMessageType.loopEnd, 0, 0, 0);
  }

  static MidiMessage endOfTrack() {
    return new MidiMessage(MidiMessageType.endOfTrack, 0, 0, 0);
  }

  @override
  String toString() {
    switch (channel) {
      case MidiMessageType.tempoChange:
        return "Tempo: $tempo";

      case MidiMessageType.loopStart:
        return "LoopStart";

      case MidiMessageType.loopEnd:
        return "LoopEnd";

      case MidiMessageType.endOfTrack:
        return "EndOfTrack";
      default:
        return "CH $channel: ${command.toRadixString(16)}, ${data1.toRadixString(16)}, ${data2.toRadixString(16)}";
    }
  }

  int get type {
    switch (channel) {
      case MidiMessageType.tempoChange:
        return MidiMessageType.tempoChange;

      case MidiMessageType.loopStart:
        return MidiMessageType.loopStart;

      case MidiMessageType.loopEnd:
        return MidiMessageType.loopEnd;

      case MidiMessageType.endOfTrack:
        return MidiMessageType.endOfTrack;

      default:
        return MidiMessageType.normal;
    }
  }

  double get tempo => 60000000.0 / ((command << 16) | (data1 << 8) | data2);
}
