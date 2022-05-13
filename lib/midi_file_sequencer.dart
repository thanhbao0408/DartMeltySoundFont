import 'dart:async';
import 'dart:core';
import 'dart:math';

import 'dart_melty_soundfont.dart';

class MidiFileSequencer extends IAudioRenderer {
  late Synthesizer _synthesizer;
  late double _speed;
  MidiFile? _midiFile;
  bool _loop = false;
  int _blockWrote = 0;
  Duration _currentTime = Duration.zero;
  int _msgIndex = 0;
  int _loopIndex = 0;
  late ByteData _blockLeft;
  late ByteData _blockRight;

  final StreamController<MidiMessage> _messageController =
      StreamController<MidiMessage>();

  /// Initializes a new instance of the sequencer.
  MidiFileSequencer(Synthesizer synthesizer) {
    _synthesizer = synthesizer;
    _blockLeft = ByteData(Float32List.bytesPerElement * _synthesizer.blockSize);
    _blockRight =
        ByteData(Float32List.bytesPerElement * _synthesizer.blockSize);
    _speed = 1.0;
  }

  Stream<MidiMessage>? get onMidiMessage {
    return _messageController.stream;
  }

  /// Plays the MIDI file.
  /// <param name="midiFile">The MIDI file to be played.</param>
  /// <param name="loop">If <c>true</c>, the MIDI file loops after reaching the end.</param>
  void play(MidiFile midiFile, bool loop) {
    _midiFile = midiFile;
    _loop = loop;
    _blockWrote = _synthesizer.blockSize;
    _currentTime = Duration.zero;
    _msgIndex = 0;
    _loopIndex = 0;
    _synthesizer.reset();
  }

  /// Stop playing.
  void stop() {
    _midiFile = null;
    _synthesizer.reset();
  }

  @override
  void render(List<double> left, List<double> right) {
    if (left.length != right.length) {
      throw "The output buffers must be the same length.";
    }

    var wrote = 0;
    while (wrote < left.length) {
      if (_blockWrote == _synthesizer.blockSize) {
        _processEvents();
        _blockWrote = 0;
        _currentTime += MidiFile.getTimeSpanFromSeconds(
            _speed * _synthesizer.blockSize / _synthesizer.sampleRate);
      }

      var srcRemainder = _synthesizer.blockSize - _blockWrote;
      var dstRemainder = left.length - wrote;
      var remainder = min(srcRemainder, dstRemainder);
      //C# code
      //Slice: Forms a slice out of the current span starting at a specified index for a specified length.
      //synthesizer.Render(left.Slice(wrote, rem), right.Slice(wrote, rem));

      // I did not test which one is faster but allocation for every iteration might possibly be slower so I chose the Float32List.view option
      // var blockLeft = Float32List(remainder);
      // var blockRight = Float32List(remainder);
      var blockLeft = Float32List.view(_blockLeft.buffer, 0, remainder);
      var blockRight = Float32List.view(_blockRight.buffer, 0, remainder);

      _synthesizer.render(blockLeft, blockRight);
      for (int i = 0; i < remainder; i++) {
        left[wrote + i] = blockLeft[i];
        right[wrote + i] = blockRight[i];
      }

      _blockWrote += remainder;
      wrote += remainder;
    }
  }

  void _processEvents() {
    if (_midiFile == null) {
      return;
    }
    while (_msgIndex < _midiFile!.messages.length) {
      var time = _midiFile!.times[_msgIndex];
      var msg = _midiFile!.messages[_msgIndex];
      if (time <= _currentTime) {
        if (msg.type == MidiMessageType.normal) {
          //print("$msg");
          _messageController.add(msg);
          _synthesizer.processMidiMessage(
              channel: msg.channel,
              command: msg.command,
              data1: msg.data1,
              data2: msg.data2);
        } else if (_loop) {
          if (msg.type == MidiMessageType.loopStart) {
            _loopIndex = _msgIndex;
          } else if (msg.type == MidiMessageType.loopEnd) {
            _currentTime = _midiFile!.times[_loopIndex];
            _msgIndex = _loopIndex;
            _synthesizer.noteOffAll(immediate: false);
          }
        }
        _msgIndex++;
      } else {
        break;
      }
    }

    if (_msgIndex == _midiFile!.messages.length && _loop) {
      _currentTime = _midiFile!.times[_loopIndex];
      _msgIndex = _loopIndex;
      _synthesizer.noteOffAll(immediate: false);
    }
  }

  /// Gets the current playback position.
  Duration get position => _currentTime;

  /// Gets a value that indicates whether the current playback position is at the end of the sequence.
  /// If the Play method has not yet been called, this value is true.
  /// This value will never be true if loop playback is enabled.
  bool get EndOfSequence {
    if (_midiFile == null) {
      return true;
    } else {
      return _msgIndex == _midiFile!.messages.length;
    }
  }

  /// Gets or sets the playback speed.
  /// The default value is 1.
  /// The tempo will be multiplied by this value.
  double get speed => _speed;
  void set speed(double val) {
    if (val > 0) {
      _speed = val;
    } else {
      throw "The playback speed must be a positive value.";
    }
  }
}
