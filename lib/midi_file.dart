import 'dart:typed_data';

import 'binary_reader.dart';
import 'midi_file_loop_type.dart';

class MidiFile {
  int trackCount;
  int resolution;
  List<Message> messages;
  List<Duration> times;

  MidiFile(this.trackCount, this.resolution, this.messages, this.times);

  factory MidiFile.fromFile(String filePath) {
    BinaryReader reader = BinaryReader.fromFile(filePath);
    return MidiFile.fromBinaryReader(reader, 0, MidiFileLoopType.none);
  }

  factory MidiFile.fromByteData(ByteData bytes) {
    BinaryReader reader = BinaryReader.fromByteData(bytes);
    return MidiFile.fromBinaryReader(reader, 0, MidiFileLoopType.none);
  }

  factory MidiFile.fromBinaryReader(
      BinaryReader reader, int loopPoint, MidiFileLoopType loopType) {
    var chunkType = reader.readFourCC();
    if (chunkType != "MThd") {
      throw "The chunk type must be 'MThd', but was '${chunkType}'.";
    }
    var size = reader.readInt32BigEndian();
    if (size != 6) {
      throw "The MThd chunk has invalid data.";
    }
    var format = reader.readInt16BigEndian();
    if (!(format == 0 || format == 1)) {
      throw "The format ${format} is not supported.";
    }
    int trackCount = reader.readInt16BigEndian();
    int resolution = reader.readInt16BigEndian();
    List<List<Message>> messageLists = [];
    List<List<int>> tickLists = [];
    for (var i = 0; i < trackCount; i++) {
      List<Message> messageList = [];
      List<int> tickList = [];
      _readTrack(reader, loopType, messageList, tickList);
      messageLists.add(messageList);
      tickLists.add(tickList);
    }
    if (loopPoint != 0) {
      var tickList = tickLists[0];
      var messageList = messageLists[0];
      if (loopPoint <= tickList.last) {
        for (var i = 0; i < tickList.length; i++) {
          if (tickList[i] >= loopPoint) {
            tickList.insert(i, loopPoint);
            messageList.insert(i, Message.loopStart());
            break;
          }
        }
      } else {
        tickList.add(loopPoint);
        messageList.add(Message.loopStart());
      }
    }

    List<Message> messages = [];
    List<Duration> times = [];
    _mergeTracks(messageLists, tickLists, resolution, messages, times);

    return MidiFile(trackCount, resolution, messages, times);
  }

  static Duration getTimeSpanFromSeconds(double value) {
    return Duration(
        milliseconds: (Duration.millisecondsPerSecond * value).toInt());
  }

  static int _checkedAdd(int a, int b) {
    var sum = a + b;
    if (a > 0 && b > 0 && sum < 0) {
      throw "int OverflowException(positive: true)";
    }
    if (a < 0 && b < 0 && sum > 0) {
      throw "OverflowException(positive: false)";
    }
    return sum;
  }

  static void _readTrack(BinaryReader reader, MidiFileLoopType loopType,
      List<Message> messages, List<int> ticks) {
    var chunkType = reader.readFourCC();
    if (chunkType != "MTrk") {
      throw "The chunk type must be 'MTrk', but was '${chunkType}'.";
    }
    reader.readInt32BigEndian();
    int tick = 0;
    int lastStatus = 0; //byte
    while (true) {
      var delta = reader.readMidiVariablelength();
      var first = reader.readUInt8();

      try {
        tick = _checkedAdd(tick, delta);
      } catch (e) {
        throw "Long MIDI file is not supported.";
      }
      if ((first & 128) == 0) {
        var command = lastStatus & 0xF0;
        if (command == 0xC0 || command == 0xD0) {
          messages.add(Message.common1(lastStatus, first));
          ticks.add(tick);
        } else {
          var data2 = reader.readUInt8();
          messages.add(Message.common2(lastStatus, first, data2, loopType));
          ticks.add(tick);
        }

        continue;
      }
      switch (first) {
        case 0xF0: // System Exclusive
          _discardData(reader);
          break;

        case 0xF7: // System Exclusive
          _discardData(reader);
          break;

        case 0xFF: // Meta Event
          switch (reader.readUInt8()) {
            case 0x2F: // End of Track
              reader.readUInt8();
              messages.add(Message.endOfTrack());
              ticks.add(tick);
              return;

            case 0x51: // Tempo
              messages.add(Message.tempoChange(_readTempo(reader)));
              ticks.add(tick);
              break;

            default:
              _discardData(reader);
              break;
          }
          break;

        default:
          var command = first & 0xF0;
          if (command == 0xC0 || command == 0xD0) {
            var data1 = reader.readUInt8();
            messages.add(Message.common1(first, data1));
            ticks.add(tick);
          } else {
            var data1 = reader.readUInt8();
            var data2 = reader.readUInt8();
            messages.add(Message.common2(first, data1, data2, loopType));
            ticks.add(tick);
          }
          break;
      }

      lastStatus = first;
    }
  }

  static void _mergeTracks(
      List<List<Message>> messageLists,
      List<List<int>> tickLists,
      int resolution,
      List<Message> messages,
      List<Duration> times) {
    var indices = List<int>.filled(messageLists.length, 0);

    var currentTick = 0;
    var currentTime = Duration.zero;

    var tempo = 120.0;

    while (true) {
      var minTick = 0x7fffffffffffffff;
      var minIndex = -1;
      for (var ch = 0; ch < tickLists.length; ch++) {
        if (indices[ch] < tickLists[ch].length) {
          var tick = tickLists[ch][indices[ch]];
          if (tick < minTick) {
            minTick = tick;
            minIndex = ch;
          }
        }
      }

      if (minIndex == -1) {
        break;
      }

      var nextTick = tickLists[minIndex][indices[minIndex]];
      var deltaTick = nextTick - currentTick;
      var deltaTime =
          getTimeSpanFromSeconds(60.0 / (resolution * tempo) * deltaTick);
      currentTick += deltaTick;
      currentTime += deltaTime;

      var message = messageLists[minIndex][indices[minIndex]];
      if (message.type == MessageType.tempoChange) {
        tempo = message.tempo;
      } else {
        messages.add(message);
        times.add(currentTime);
      }

      indices[minIndex]++;
    }
  }

  static int _readTempo(BinaryReader reader) {
    var size = reader.readMidiVariablelength();
    if (size != 3) {
      throw "Failed to read the tempo value.";
    }

    var b1 = reader.readUInt8();
    var b2 = reader.readUInt8();
    var b3 = reader.readUInt8();
    return (b1 << 16) | (b2 << 8) | b3;
  }

  static void _discardData(BinaryReader reader) {
    var size = reader.readMidiVariablelength();
    reader.pos += size;
  }

  /// The length of the MIDI file.
  Duration get length => times.last;
}

class MessageType {
  static const int normal = 0;
  static const int tempoChange = 252;
  static const int loopStart = 253;
  static const int loopEnd = 254;
  static const int endOfTrack = 255;
}

class Message {
  int channel;
  int command;
  int data1;
  int data2;

  Message(int this.channel, int this.command, int this.data1, int this.data2);

  factory Message.common1(int status, int data1) {
    int channel = (status & 0x0F);
    int command = (status & 0xF0);
    int data2 = 0;
    return Message(channel, command, data1, data2);
  }

  factory Message.common2(
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
      }
    }

    return Message(channel, command, data1, data2);
  }

  static Message tempoChange(int tempo) {
    int command = (tempo >> 16);
    int data1 = (tempo >> 8);
    int data2 = tempo;
    return new Message(MessageType.tempoChange, command, data1, data2);
  }

  static Message loopStart() {
    return new Message(MessageType.loopStart, 0, 0, 0);
  }

  static Message loopEnd() {
    return new Message(MessageType.loopEnd, 0, 0, 0);
  }

  static Message endOfTrack() {
    return new Message(MessageType.endOfTrack, 0, 0, 0);
  }

  @override
  String toString() {
    switch (channel) {
      case MessageType.tempoChange:
        return "Tempo: $tempo";

      case MessageType.loopStart:
        return "LoopStart";

      case MessageType.loopEnd:
        return "LoopEnd";

      case MessageType.endOfTrack:
        return "EndOfTrack";
      default:
        return "CH $channel: ${command.toRadixString(16)}, ${data1.toRadixString(16)}, ${data2.toRadixString(16)}";
    }
  }

  int get type {
    switch (channel) {
      case MessageType.tempoChange:
        return MessageType.tempoChange;

      case MessageType.loopStart:
        return MessageType.loopStart;

      case MessageType.loopEnd:
        return MessageType.loopEnd;

      case MessageType.endOfTrack:
        return MessageType.endOfTrack;

      default:
        return MessageType.normal;
    }
  }

  double get tempo => 60000000.0 / ((command << 16) | (data1 << 8) | data2);
}
