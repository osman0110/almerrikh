import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';

// Shared widgets for training session screens

class SessionNumberSelector extends StatelessWidget {
  const SessionNumberSelector({
    super.key,
    required this.value,
    required this.count,
    required this.activeColor,
    required this.onChanged,
  });
  final int value;
  final int count;
  final Color activeColor;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: List.generate(count, (i) {
          final n   = i + 1;
          final sel = n == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(n),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                height: 40,
                decoration: BoxDecoration(
                  color: sel
                      ? activeColor.withOpacity(0.18)
                      : AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel
                        ? activeColor
                        : AppColors.border,
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Center(
                  child: Text('$n',
                      style: TextStyle(
                        color: sel
                            ? activeColor
                            : AppColors.foreground.withOpacity(0.50),
                        fontSize: 14,
                        fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                      )),
                ),
              ),
            ),
          );
        }),
      );
}

class SessionToggleBtn extends StatelessWidget {
  const SessionToggleBtn({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? color.withOpacity(0.15)
                : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? color : AppColors.foreground.withOpacity(0.45),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              )),
        ),
      );
}

class SessionPainToggle extends StatelessWidget {
  const SessionPainToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.noPainLabel = 'No Pain',
    this.painLabel = 'Pain Today',
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final String noPainLabel;
  final String painLabel;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: SessionToggleBtn(
            label: noPainLabel,
            selected: !value,
            color: AppColors.success,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SessionToggleBtn(
            label: painLabel,
            selected: value,
            color: AppColors.destructive,
            onTap: () => onChanged(true),
          ),
        ),
      ]);
}

class SessionSubmitBar extends StatelessWidget {
  const SessionSubmitBar({
    super.key,
    required this.label,
    required this.enabled,
    required this.loading,
    required this.onTap,
  });
  final String label;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: enabled && !loading ? onTap : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.foreground,
              disabledBackgroundColor:
                  AppColors.primary.withOpacity(0.25),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: AppColors.foreground, strokeWidth: 2.5))
                : Text(label,
                    style: const TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
          ),
        ),
      );
}

InputDecoration sessionInputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle:
          TextStyle(color: AppColors.foreground.withOpacity(0.30), fontSize: 13),
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

/// One clear row inside a session/match details sheet — shows whether the
/// player has submitted Hooper or RPE for that event, the actual value if
/// they have, and a direct button to submit when it's their turn to.
class WellnessDetailRow extends StatelessWidget {
  const WellnessDetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.done,
    required this.score,
    required this.actionable,
    required this.isRequired,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool done;
  final int? score;
  final bool actionable;
  final bool isRequired;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppColors.success
        : actionable
            ? AppColors.primary
            : AppColors.muted;
    final statusText = done
        ? (score != null
            ? '${AppLocalizations.get('already_submitted_label')} ($score)'
            : AppLocalizations.get('already_submitted_label'))
        : !isRequired
            ? AppLocalizations.get('wellness_not_required')
            : actionable
                ? AppLocalizations.get('wellness_tap_to_submit')
                : AppLocalizations.get('wellness_not_available_yet');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (actionable && !done)
            ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(
                AppLocalizations.get('submit_now_label'),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}
