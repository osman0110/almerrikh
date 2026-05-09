import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class LoopingVideoBackground extends StatefulWidget {
  const LoopingVideoBackground({
    super.key,
    required this.asset,
  });

  final String asset;

  @override
  State<LoopingVideoBackground> createState() => _LoopingVideoBackgroundState();
}

class _LoopingVideoBackgroundState extends State<LoopingVideoBackground> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(
      widget.asset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    )
      ..setLooping(true)
      ..setVolume(0);
    _controller.initialize().then((_) async {
      if (!mounted) return;
      await _controller.seekTo(Duration.zero);
      await _controller.play();
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videoSize = _controller.value.size;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        AnimatedOpacity(
          opacity: _ready ? 1 : 0,
          duration: const Duration(milliseconds: 450),
          child: _ready && videoSize.width > 0 && videoSize.height > 0
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: videoSize.width,
                    height: videoSize.height,
                    child: VideoPlayer(_controller),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
