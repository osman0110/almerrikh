import 'package:flutter/material.dart';

class CameraPreviewView extends StatelessWidget {
  const CameraPreviewView({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const Text(
        'Camera preview',
        style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
      ),
    );
  }
}
