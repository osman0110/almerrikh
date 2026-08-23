import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app_colors.dart';

/// Scrubs through the grayscale frame sequence captured during an AI
/// assessment so a coach can visually review the movement before certifying
/// the score. Not a real video file — see AssessmentVideoService for why.
class AssessmentFramePlayer extends StatefulWidget {
  const AssessmentFramePlayer({super.key, required this.framePaths});

  final List<String> framePaths;

  @override
  State<AssessmentFramePlayer> createState() => _AssessmentFramePlayerState();
}

class _AssessmentFramePlayerState extends State<AssessmentFramePlayer> {
  Timer? _timer;
  int _index = 0;
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _startPlayback();
  }

  void _startPlayback() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 120), (t) {
      if (!mounted || widget.framePaths.isEmpty) return;
      setState(() => _index = (_index + 1) % widget.framePaths.length);
    });
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _startPlayback();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.framePaths.isEmpty) return const SizedBox.shrink();
    final path = widget.framePaths[_index.clamp(0, widget.framePaths.length - 1)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              color: Colors.black,
              child: Image.file(File(path), fit: BoxFit.contain, gaplessPlayback: true),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              onPressed: _togglePlay,
              icon: Icon(_playing ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                  color: AppColors.primary, size: 30),
            ),
            Expanded(
              child: Slider(
                value: _index.toDouble().clamp(0, widget.framePaths.length - 1),
                min: 0,
                max: (widget.framePaths.length - 1).toDouble(),
                divisions: widget.framePaths.length > 1 ? widget.framePaths.length - 1 : null,
                activeColor: AppColors.primary,
                onChanged: (v) {
                  _timer?.cancel();
                  _playing = false;
                  setState(() => _index = v.round());
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
