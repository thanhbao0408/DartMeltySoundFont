import 'dart:core';
import 'dart:math';

import 'dart_melty_soundfont.dart';
import 'iaudio_renderer.dart';
import 'midi_file.dart';

class MidiFileSequencer extends IAudioRenderer {
  late Synthesizer _synthesizer;
  late double _speed;
  MidiFile? _midiFile;
  late bool _loop;
  late int _blockWrote;
  late Duration _currentTime;
  late int _msgIndex;
  late int _loopIndex;

  /// Initializes a new instance of the sequencer.
  MidiFileSequencer(Synthesizer synthesizer) {
    _synthesizer = synthesizer;
    _speed = 1.0;
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

      var srcRem = _synthesizer.blockSize - _blockWrote;
      var dstRem = left.length - wrote;
      var rem = min(srcRem, dstRem);

      _synthesizer.render(
          left.sublist(wrote, wrote + rem), right.sublist(wrote, wrote + rem));

      _blockWrote += rem;
      wrote += rem;
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
        if (msg.type == MessageType.normal) {
          _synthesizer.processMidiMessage(
              channel: msg.channel,
              command: msg.command,
              data1: msg.data1,
              data2: msg.data2);
        } else if (_loop) {
          if (msg.type == MessageType.loopStart) {
            _loopIndex = _msgIndex;
          } else if (msg.type == MessageType.loopEnd) {
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
