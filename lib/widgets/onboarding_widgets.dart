import 'package:flutter/material.dart';

const _neonGreen = Color(0xFFF7B638); // Al Merrikh gold

class OnboardingImageStage extends StatelessWidget {
  const OnboardingImageStage({
    super.key,
    required this.asset,
    this.dark = false,
  });

  final String asset;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xff071008), Color(0xff020302)]
              : const [Color(0xfffffbfb), Color(0xFFF0EEE7)],
        ),
      ),
      child: SizedBox.expand(
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class LanguageOptionTile extends StatelessWidget {
  const LanguageOptionTile({
    super.key,
    required this.name,
    required this.label,
    required this.icon,
    required this.selected,
    required this.textStyle,
    required this.onTap,
  });

  final String name;
  final String label;
  final IconData icon;
  final bool selected;
  final TextStyle textStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _neonGreen : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: selected
                ? _neonGreen.withOpacity(0.15)
                : Colors.white.withOpacity(0.07),
            border: Border.all(
              color: selected
                  ? _neonGreen.withOpacity(0.95)
                  : Colors.white.withOpacity(0.13),
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.38),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withOpacity(0.30)),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle.copyWith(
                    color: selected ? _neonGreen : Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? _neonGreen : Colors.white30,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LanguageContinueButton extends StatelessWidget {
  const LanguageContinueButton({
    super.key,
    required this.enabled,
    required this.text,
    required this.textStyle,
    required this.onTap,
  });

  final bool enabled;
  final String text;
  final TextStyle textStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_neonGreen, Color(0xff20cc00)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: _neonGreen.withOpacity(0.38),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              text,
              style: textStyle.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _neonGreen
      ..strokeWidth = 0.5;

    for (int i = 0; i < 14; i++) {
      canvas.drawLine(
        Offset(i * 30.0, 0),
        Offset(i * 30.0, size.height),
        paint,
      );
    }

    for (int i = 0; i < 29; i++) {
      canvas.drawLine(Offset(0, i * 30.0), Offset(size.width, i * 30.0), paint);
    }
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) => false;
}
