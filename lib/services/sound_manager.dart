import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SoundEvent {
  countdownTick,   // 3 · 2 · 1
  countdownGo,     // Go!
  workoutStart,    // Training begins
  targetAppear,    // New target shown
  targetHit,       // Successful tap
  targetMiss,      // Timeout / missed
  workoutComplete, // All done
  timeWarning,     // Last few seconds
}

/// Generates and plays short synthesised tones – no audio asset files needed.
/// Tones are pre-built once at [init] and cached for zero-latency playback.
class SoundManager {
  SoundManager._();
  static final SoundManager instance = SoundManager._();

  static const _prefKey = 'ssot.soundEnabled';
  static const _sampleRate = 22050; // Hz — good quality, small buffers

  bool _enabled = true;
  bool get enabled => _enabled;

  final Map<SoundEvent, Uint8List> _cache = {};

  // ── Public API ────────────────────────────────────────────────────

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefKey) ?? true;
    } catch (_) {}
    // Pre-build all tones so first call has no latency.
    for (final e in SoundEvent.values) {
      _cache[e] = _generate(e);
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
  }

  /// Fire-and-forget: creates a short-lived player, plays, then disposes it.
  Future<void> play(SoundEvent event) async {
    if (!_enabled) return;
    try {
      final bytes = _cache[event] ?? _generate(event);
      final player = AudioPlayer();
      await player.play(BytesSource(bytes));
      player.onPlayerComplete.first.then((_) => player.dispose());
    } catch (e) {
      debugPrint('[SoundManager] play error: $e');
    }
  }

  // ── Tone definitions per event ────────────────────────────────────

  Uint8List _generate(SoundEvent event) => switch (event) {
        SoundEvent.countdownTick   => _sine(440, 110, 0.55),
        SoundEvent.countdownGo     => _chord([659, 880, 1109], 220, 0.65),
        SoundEvent.workoutStart    => _chord([523, 659, 784], 280, 0.60),
        SoundEvent.targetAppear    => _sine(700, 55, 0.28),
        SoundEvent.targetHit       => _chirp(600, 950, 140, 0.70),
        SoundEvent.targetMiss      => _sine(200, 170, 0.40),
        SoundEvent.workoutComplete => _completionFanfare(),
        SoundEvent.timeWarning     => _doubleBeep(440, 80, 0.42),
      };

  // ── Synthesisers ─────────────────────────────────────────────────

  /// Single sustained sine wave with fade-in / fade-out envelope.
  Uint8List _sine(double freq, int ms, double vol) {
    final n = _ns(ms);
    final s = Int16List(n);
    final amp = (32767 * vol).round();
    for (int i = 0; i < n; i++) {
      s[i] = (_env(i, n) * amp * math.sin(2 * math.pi * freq * i / _sampleRate))
          .round()
          .clamp(-32768, 32767);
    }
    return _wav(s);
  }

  /// Mix of multiple frequencies (chord / harmony).
  Uint8List _chord(List<double> freqs, int ms, double vol) {
    final n = _ns(ms);
    final s = Int16List(n);
    final amp = (32767 * vol / freqs.length).round();
    for (int i = 0; i < n; i++) {
      int v = 0;
      for (final f in freqs) {
        v += (amp * math.sin(2 * math.pi * f * i / _sampleRate)).round();
      }
      s[i] = (_env(i, n) * v).round().clamp(-32768, 32767);
    }
    return _wav(s);
  }

  /// Rising-pitch chirp — satisfying "ding" on success.
  Uint8List _chirp(double f0, double f1, int ms, double vol) {
    final n = _ns(ms);
    final s = Int16List(n);
    final amp = (32767 * vol).round();
    double phase = 0;
    for (int i = 0; i < n; i++) {
      final freq = f0 + (f1 - f0) * (i / n);
      phase += 2 * math.pi * freq / _sampleRate;
      s[i] = (_env(i, n) * amp * math.sin(phase)).round().clamp(-32768, 32767);
    }
    return _wav(s);
  }

  /// Ascending four-note fanfare for workout completion.
  Uint8List _completionFanfare() {
    final notes = [523.0, 659.0, 784.0, 1047.0];
    final parts = <Int16List>[];
    for (int k = 0; k < notes.length; k++) {
      final n = _ns(155);
      final s = Int16List(n);
      final amp = (32767 * 0.55).round();
      for (int i = 0; i < n; i++) {
        s[i] = (_env(i, n) * amp *
                math.sin(2 * math.pi * notes[k] * i / _sampleRate))
            .round()
            .clamp(-32768, 32767);
      }
      parts.add(s);
      if (k < notes.length - 1) parts.add(Int16List(_ns(28))); // tiny gap
    }
    final total = parts.fold(0, (sum, l) => sum + l.length);
    final merged = Int16List(total);
    int off = 0;
    for (final p in parts) {
      merged.setRange(off, off + p.length, p);
      off += p.length;
    }
    return _wav(merged);
  }

  /// Two short blips — used for time warning.
  Uint8List _doubleBeep(double freq, int ms, double vol) {
    final beep = _ns(ms);
    final gap  = _ns(55);
    final s = Int16List(beep * 2 + gap);
    final amp = (32767 * vol).round();
    for (int b = 0; b < 2; b++) {
      final start = b * (beep + gap);
      for (int i = 0; i < beep; i++) {
        s[start + i] = (_env(i, beep) * amp *
                math.sin(2 * math.pi * freq * i / _sampleRate))
            .round()
            .clamp(-32768, 32767);
      }
    }
    return _wav(s);
  }

  // ── Helpers ───────────────────────────────────────────────────────

  int _ns(int ms) => (_sampleRate * ms / 1000).round();

  /// Smooth amplitude envelope: 5 % fade-in, 15 % fade-out.
  double _env(int i, int n) {
    if (i < n * 0.05) return i / (n * 0.05);
    if (i > n * 0.85) return (n - i) / (n * 0.15);
    return 1.0;
  }

  /// Encode Int16List as a standard PCM WAV (mono, 16-bit, [_sampleRate] Hz).
  Uint8List _wav(Int16List samples) {
    final dataBytes = samples.length * 2;
    final buf = ByteData(44 + dataBytes);

    void str(int off, String s) {
      for (int i = 0; i < s.length; i++) buf.setUint8(off + i, s.codeUnitAt(i));
    }

    str(0, 'RIFF');
    buf.setUint32(4,  36 + dataBytes,      Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    buf.setUint32(16, 16,                  Endian.little); // fmt chunk size
    buf.setUint16(20, 1,                   Endian.little); // PCM
    buf.setUint16(22, 1,                   Endian.little); // mono
    buf.setUint32(24, _sampleRate,         Endian.little);
    buf.setUint32(28, _sampleRate * 2,     Endian.little); // byteRate
    buf.setUint16(32, 2,                   Endian.little); // blockAlign
    buf.setUint16(34, 16,                  Endian.little); // bitsPerSample
    str(36, 'data');
    buf.setUint32(40, dataBytes,           Endian.little);
    for (int i = 0; i < samples.length; i++) {
      buf.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return buf.buffer.asUint8List();
  }
}
