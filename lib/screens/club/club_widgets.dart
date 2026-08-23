/// Shared UI widgets for all club management screens.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../shared/club_ui_tokens.dart';
import 'notifications_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AddButton
// ─────────────────────────────────────────────────────────────────────────────

class ClubAddButton extends StatelessWidget {
  const ClubAddButton({super.key, required this.onTap, this.label = 'Add'});
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.30),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, color: AppColors.foreground, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                  color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FormHeader
// ─────────────────────────────────────────────────────────────────────────────

class ClubFormHeader extends StatelessWidget {
  const ClubFormHeader({
    super.key,
    required this.title,
    required this.onBack,
    required this.onSave,
    this.saving = false,
  });
  final String title;
  final VoidCallback onBack;
  final VoidCallback? onSave;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.close_rounded, color: AppColors.foreground, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                  color: AppColors.foreground, fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),
          if (onSave != null)
            GestureDetector(
              onTap: onSave,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.30),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.foreground),
                      )
                    : Text(
                        AppLocalizations.get('save_btn'),
                        style: const TextStyle(
                            color: AppColors.foreground,
                            fontWeight: FontWeight.w800,
                            fontSize: 14),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FormField
// ─────────────────────────────────────────────────────────────────────────────

class ClubFormField extends StatelessWidget {
  const ClubFormField({
    super.key,
    required this.controller,
    required this.label,
    this.hint = '',
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: const TextStyle(color: AppColors.foreground, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
            filled: true,
            fillColor: AppColors.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DropdownField
// ─────────────────────────────────────────────────────────────────────────────

class ClubDropdownField<T> extends StatelessWidget {
  const ClubDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: AppColors.card,
            underline: const SizedBox(),
            style: const TextStyle(color: AppColors.foreground, fontSize: 14),
            items: items
                .map((e) => DropdownMenuItem(value: e, child: Text(labelOf(e))))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ConfirmDialog
// ─────────────────────────────────────────────────────────────────────────────

class ClubConfirmDialog extends StatelessWidget {
  const ClubConfirmDialog({
    super.key,
    required this.title,
    required this.body,
    this.confirmLabel,
    this.confirmColor = AppColors.destructive,
  });
  final String title;
  final String body;
  final String? confirmLabel;
  final Color confirmColor;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      title: Text(
        title,
        style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w900),
      ),
      content: Text(
        body,
        style: const TextStyle(color: AppColors.muted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(AppLocalizations.get('cancel'),
              style: const TextStyle(color: AppColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmLabel ?? AppLocalizations.get('confirm'),
            style: TextStyle(
              color: confirmColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PageHeader — back button + title + optional action
// ─────────────────────────────────────────────────────────────────────────────

class ClubPageHeader extends StatelessWidget {
  const ClubPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onBack,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 16, 20, 14),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.foreground, size: 18),
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SectionLabel
// ─────────────────────────────────────────────────────────────────────────────

class ClubSectionLabel extends StatelessWidget {
  const ClubSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ScoreRing — small circular score indicator
// ─────────────────────────────────────────────────────────────────────────────

class ClubScoreRing extends StatelessWidget {
  const ClubScoreRing({
    super.key,
    required this.score,
    this.size = 64,
    this.strokeWidth = 5,
    this.label,
  });
  final double score;
  final double size;
  final double strokeWidth;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? AppColors.success
        : score >= 60
            ? AppColors.warning
            : AppColors.destructive;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(score / 100, color, strokeWidth),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score.toStringAsFixed(0),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.22,
                  height: 1,
                ),
              ),
              if (label != null)
                Text(
                  label!,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: size * 0.13,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppHeader — unified header for club screens (dashboard/players/matches/reports)
// ─────────────────────────────────────────────────────────────────────────────

class PhysicalCoachSidebarScope extends InheritedWidget {
  const PhysicalCoachSidebarScope({
    super.key,
    required this.openSidebar,
    required super.child,
  });

  final VoidCallback openSidebar;

  static PhysicalCoachSidebarScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PhysicalCoachSidebarScope>();

  @override
  // The callback belongs to the shell's Scaffold and does not represent
  // display data. Notifying dependents whenever the shell rebuilds can mark
  // headers dirty while a route is being replaced, which may leave inherited
  // dependents in the wrong build scope.
  bool updateShouldNotify(PhysicalCoachSidebarScope oldWidget) => false;
}

class ClubAppHeader extends StatelessWidget implements PreferredSizeWidget {
  const ClubAppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.showMenuButton = true,
    this.transparent = false,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  // Set to false when a CoachBrandHeader above this one already owns the
  // sidebar-opening hamburger button, so it isn't shown twice.
  final bool showMenuButton;
  // Set to true when this header sits directly under a CoachBrandHeader —
  // the card/border look is only meant for standalone page headers.
  final bool transparent;

  static const double height = 64;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final sidebar = showMenuButton ? PhysicalCoachSidebarScope.maybeOf(context) : null;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: transparent
          ? const BoxDecoration(color: Colors.transparent)
          : const BoxDecoration(
              color: AppColors.card,
              border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
            ),
      child: Row(
        children: [
          if (sidebar != null)
            GestureDetector(
              onTap: sidebar.openSidebar,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.menu_rounded,
                  color: AppColors.foreground,
                  size: 20,
                ),
              ),
            ),
          if (sidebar != null)
            const SizedBox(width: 10)
          else if (leading != null)
            leading!
          else
            const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RoleBrandHeader — shared top identity bar for every club-facing role.
// Keeps the physical-coach visual language while allowing each role to retain
// its own page title, actions, navigation callback, and business workflow.
// ─────────────────────────────────────────────────────────────────────────────

class RoleBrandHeader extends StatelessWidget {
  const RoleBrandHeader({
    super.key,
    required this.roleLabel,
    this.accountName,
    this.pageTitle,
    this.subtitle,
    this.onMenuTap,
    this.showMenuButton = true,
    this.trailing,
  });

  final String roleLabel;
  final String? accountName;
  final String? pageTitle;
  final String? subtitle;
  final VoidCallback? onMenuTap;
  final bool showMenuButton;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final sidebar = PhysicalCoachSidebarScope.maybeOf(context);
    final clubDisplay = AppLocalizations.get('club_brand_name');
    final displayName = accountName?.trim().isNotEmpty == true
        ? accountName!.trim()
        : currentUserName.trim().isNotEmpty
            ? currentUserName.trim()
            : roleLabel;
    final openMenu = onMenuTap ?? sidebar?.openSidebar;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                if (showMenuButton && openMenu != null)
                  GestureDetector(
                    onTap: openMenu,
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: Icon(
                        Icons.menu_rounded,
                        color: AppColors.foreground,
                        size: 20,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 28, height: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ClipOval(
                            child: Image.asset(
                              'assets/images/blacklogo.webp',
                              width: 30,
                              height: 30,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              clubDisplay,
                              style: const TextStyle(
                                color: AppColors.foreground,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                        if (isDoctorRole)
                          Text(
                            getAppLanguage() == 'ar'
                                ? '$displayName — $roleLabel'
                                : '$roleLabel — $displayName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: getAppLanguage() == 'ar'
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            textDirection: getAppLanguage() == 'ar'
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            children: [
                              Text(
                                '$roleLabel · ',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Flexible(
                                child: Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                trailing ?? const NotificationBellButton(),
              ],
            ),
          ),
          if (pageTitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pageTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.foreground,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RoleDateMarker {
  const RoleDateMarker({
    this.hasMatch = false,
    this.hasSession = false,
    this.accentColor,
  });

  final bool hasMatch;
  final bool hasSession;
  final Color? accentColor;
}

class RoleHomeDateStrip extends StatefulWidget {
  const RoleHomeDateStrip({
    super.key,
    this.selectedDate,
    this.onDateChanged,
    this.markerOf,
    this.onCalendarTap,
  });

  final DateTime? selectedDate;
  final ValueChanged<DateTime>? onDateChanged;
  final RoleDateMarker Function(DateTime date)? markerOf;
  final VoidCallback? onCalendarTap;

  @override
  State<RoleHomeDateStrip> createState() => _RoleHomeDateStripState();
}

class _RoleHomeDateStripState extends State<RoleHomeDateStrip> {
  late DateTime _localDate;

  @override
  void initState() {
    super.initState();
    _localDate = _dateOnly(widget.selectedDate ?? DateTime.now());
  }

  DateTime get _selectedDate =>
      _dateOnly(widget.selectedDate ?? _localDate);

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _selectDate(DateTime date) {
    final selected = _dateOnly(date);
    if (widget.selectedDate == null) {
      setState(() => _localDate = selected);
    }
    widget.onDateChanged?.call(selected);
  }

  Future<void> _pickDate() async {
    final selected = _selectedDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) _selectDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedDate;
    final window = List<DateTime>.generate(
      5,
      (index) => selected.add(Duration(days: index - 2)),
    );
    final isToday = _sameDay(selected, DateTime.now());

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _selectDate(
              selected.subtract(const Duration(days: 5)),
            ),
            child: Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_right_rounded
                  : Icons.chevron_left_rounded,
              color: AppColors.muted,
              size: 20,
            ),
          ),
          Expanded(
            child: Row(
              children: [
                for (final date in window) Expanded(child: _buildDayPill(date)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _selectDate(selected.add(const Duration(days: 5))),
            child: Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              color: AppColors.muted,
              size: 20,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: widget.onCalendarTap ?? _pickDate,
            child: const Icon(
              Icons.calendar_month_rounded,
              color: AppColors.maroon,
              size: 18,
            ),
          ),
          if (!isToday) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _selectDate(DateTime.now()),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  AppLocalizations.get('today_label'),
                  style: const TextStyle(
                    color: AppColors.maroon,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDayPill(DateTime date) {
    final selected = _selectedDate;
    final isSelected = _sameDay(date, selected);
    final isToday = _sameDay(date, DateTime.now());
    final marker = widget.markerOf?.call(date) ?? const RoleDateMarker();

    return GestureDetector(
      onTap: () => _selectDate(date),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.dayName(date),
              style: TextStyle(
                color: isSelected ? AppColors.maroon : AppColors.foreground,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
              maxLines: 1,
              softWrap: false,
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 10,
              child: marker.hasMatch
                  ? const Icon(
                      Icons.sports_soccer_rounded,
                      size: 10,
                      color: AppColors.maroon,
                    )
                  : marker.hasSession
                      ? Icon(
                          Icons.fitness_center_rounded,
                          size: 10,
                          color: marker.accentColor ?? AppColors.gold,
                        )
                      : null,
            ),
            const SizedBox(height: 4),
            Text(
              '${date.day}',
              style: TextStyle(
                color: marker.accentColor ??
                    (isSelected
                        ? AppColors.maroon
                        : isToday
                            ? AppColors.gold
                            : AppColors.muted),
                fontWeight: FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CoachBrandHeader extends StatelessWidget {
  const CoachBrandHeader({super.key});

  @override
  Widget build(BuildContext context) => RoleBrandHeader(
        roleLabel: _currentRoleLabel(),
      );
}

String _currentRoleLabel() {
  switch (currentOrgRole) {
    case OrgRole.owner:
      return AppLocalizations.get('role_owner');
    case OrgRole.admin:
      return AppLocalizations.get('role_admin');
    case OrgRole.coach:
      return AppLocalizations.get('role_coach');
    case OrgRole.doctor:
      return AppLocalizations.get('role_doctor');
    case OrgRole.physiotherapist:
      return AppLocalizations.get('role_physiotherapist');
    case OrgRole.nutritionist:
      return AppLocalizations.get('role_nutritionist');
    case OrgRole.tacticalCoach:
      return AppLocalizations.get('role_tactical_coach');
    case OrgRole.analyst:
      return AppLocalizations.get('role_analyst');
    case OrgRole.performanceManager:
      return AppLocalizations.get('role_performance_manager');
    case OrgRole.staff:
      return AppLocalizations.get('role_staff');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ClubSectionTitle — compact page-title row (icon + "Title (count)" + trailing
// action), used directly under CoachBrandHeader. Matches the design mock's
// spec exactly: 15px icon, 6px gap, 16px/w700 title, 4px top / 10px bottom.
// ─────────────────────────────────────────────────────────────────────────────

class ClubSectionTitle extends StatelessWidget {
  const ClubSectionTitle({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
    child: Row(
      children: [
        Icon(icon, color: AppColors.maroon, size: 15),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// StatusBadge — colored dot + label pill
// ─────────────────────────────────────────────────────────────────────────────

class ClubStatusBadge extends StatelessWidget {
  const ClubStatusBadge({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 4, height: 4,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 11)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MetricCard — fixed-size stat tile (icon + value + label)
// ─────────────────────────────────────────────────────────────────────────────

class ClubMetricCard extends StatelessWidget {
  const ClubMetricCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
    this.alert = false,
    this.selected = false,
    this.width = 84,
    this.compact = false,
  });
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool alert;
  final bool selected;
  final double width;
  /// Shrinks padding/icon/font so 4 cards can stay in a single row on
  /// narrow phones instead of wrapping to 2x2.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hPad = compact ? 6.0 : 10.0;
    final vPad = compact ? 8.0 : 10.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.08) : AppColors.card,
          borderRadius: BorderRadius.circular(ClubUiTokens.radiusMd),
          border: Border.all(
              color: selected
                  ? color.withOpacity(0.55)
                  : alert ? color.withOpacity(0.40) : color.withOpacity(0.20),
              width: selected ? 1.4 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(clipBehavior: Clip.none, children: [
              Icon(icon, color: color, size: compact ? 15 : 18),
              if (alert)
                Positioned(
                  right: -4, top: -4,
                  child: Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                        color: AppColors.destructive, shape: BoxShape.circle),
                  ),
                ),
            ]),
            SizedBox(height: compact ? 3 : 5),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 13 : 16,
                    height: 1)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(color: AppColors.muted, fontSize: compact ? 8.5 : 10),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EmptyState — icon + title + description + optional CTA
// ─────────────────────────────────────────────────────────────────────────────

class ClubEmptyState extends StatelessWidget {
  const ClubEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.ctaLabel,
    this.onCta,
  });
  final IconData icon;
  final String title;
  final String? description;
  final String? ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                  color: AppColors.primarySoft, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(description!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ],
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: 18),
              GestureDetector(
                onTap: onCta,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius:
                        BorderRadius.circular(ClubUiTokens.buttonRadius),
                  ),
                  child: Text(ctaLabel!,
                      style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FilterChip — pill-style filter option
// ─────────────────────────────────────────────────────────────────────────────

class ClubFilterChip extends StatelessWidget {
  const ClubFilterChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.accentColor,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.15) : AppColors.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? color.withOpacity(0.50) : AppColors.border,
            width: active ? 1.2 : 0.8,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? color : AppColors.muted,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                fontSize: 11.5)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SecondaryButton — outlined maroon action
// ─────────────────────────────────────────────────────────────────────────────

class ClubSecondaryButton extends StatelessWidget {
  const ClubSecondaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.maroon,
          side: const BorderSide(color: AppColors.maroon, width: 1.2),
          padding: const EdgeInsets.symmetric(
              vertical: ClubUiTokens.spacingMd + 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ClubUiTokens.buttonRadius),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 6),
            ],
            Text(label),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LoadingSkeleton — shimmer placeholder block
// ─────────────────────────────────────────────────────────────────────────────

class ClubLoadingSkeleton extends StatelessWidget {
  const ClubLoadingSkeleton({
    super.key,
    this.height = 84,
    this.borderRadius = ClubUiTokens.radiusLg,
  });
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ErrorState — icon + message + retry
// ─────────────────────────────────────────────────────────────────────────────

class ClubErrorState extends StatelessWidget {
  const ClubErrorState({
    super.key,
    required this.title,
    required this.description,
    required this.retryLabel,
    required this.onRetry,
  });
  final String title;
  final String description;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.destructive.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline_rounded,
                color: AppColors.destructive, size: 26),
          ),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          const SizedBox(height: 6),
          Text(description,
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(ClubUiTokens.buttonRadius),
              ),
              child: Text(retryLabel,
                  style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SectionHeader — title + optional trailing action
// ─────────────────────────────────────────────────────────────────────────────

class ClubSectionHeader extends StatelessWidget {
  const ClubSectionHeader({super.key, required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          if (action != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Text(action!,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.strokeWidth);
  final double value;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - strokeWidth / 2;
    canvas.drawCircle(
      center, radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color.withOpacity(0.12),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * value.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// NotificationBellButton — in-app notification center entry point, shared
// across every org role's Home dashboard. Fetches the unread count once on
// mount and refreshes it whenever the notifications screen is closed.
// ─────────────────────────────────────────────────────────────────────────────

class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({super.key});

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final count = await ApiService.getUnreadNotificationCount();
    if (mounted) setState(() => _unread = count);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const NotificationsPage(),
        ));
        _loadCount();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.notifications_none_rounded,
                color: AppColors.foreground, size: 19),
          ),
          if (_unread > 0)
            Positioned(
              top: -2, right: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: const BoxDecoration(
                  color: AppColors.destructive,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _unread > 9 ? '9+' : '$_unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ClubActionTile — quick-action row (icon + label + subtitle + loading state)
// shared across role dashboards (e.g. physical coach's AI test/FMS/body-fat
// quick actions).
// ─────────────────────────────────────────────────────────────────────────────

class ClubActionTile extends StatelessWidget {
  const ClubActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.isLoading = false,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isEnabled = !isLoading;
    return Semantics(
      button: true,
      enabled: isEnabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isEnabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(0.22)),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: isLoading
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          color: accent,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(icon, color: accent, size: 19),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.foreground,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: accent,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ReportDateRangeChip — shared date-range picker for report screens. Same
// visual pattern as team_performance_report_screen.dart's original filter
// chip, pulled out so every report (team + individual) can offer a custom
// time period consistently instead of each hardcoding its own window.
// ─────────────────────────────────────────────────────────────────────────────

class ReportDateRangeChip extends StatelessWidget {
  const ReportDateRangeChip({
    super.key,
    required this.value,
    required this.onChanged,
    this.firstDate,
  });
  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;
  final DateTime? firstDate;

  @override
  Widget build(BuildContext context) {
    final label = value == null
        ? AppLocalizations.get('date_range_label')
        : '${value!.start.day}/${value!.start.month} – ${value!.end.day}/${value!.end.month}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () async {
            final range = await showDateRangePicker(
              context: context,
              firstDate: firstDate ?? DateTime(2024),
              lastDate: DateTime.now(),
              initialDateRange: value,
            );
            if (range != null) onChanged(range);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.date_range_rounded, color: AppColors.muted, size: 14),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
        ),
        if (value != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: GestureDetector(
              onTap: () => onChanged(null),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.maroon.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.maroon.withOpacity(0.20)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.close_rounded, color: AppColors.maroon, size: 12),
                    const SizedBox(width: 4),
                    Text(AppLocalizations.get('clear_filters_label'),
                        style: const TextStyle(
                            color: AppColors.maroon, fontWeight: FontWeight.w700, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// showReportSectionsSheet — lets the coach add/remove sections shown on a
// report screen (checkboxes over the report's available section keys).
// Shared across every customizable report so the interaction is consistent.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showReportSectionsSheet({
  required BuildContext context,
  required List<(String key, String label)> options,
  required Set<String> initial,
  required ValueChanged<Set<String>> onSave,
}) async {
  var selected = {...initial};
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.get('report_customize_sections'),
                    style: const TextStyle(
                        color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text(AppLocalizations.get('report_customize_sections_hint'),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: options.map((o) => CheckboxListTile(
                            value: selected.contains(o.$1),
                            onChanged: (v) => setSheetState(() {
                              if (v == true) {
                                selected.add(o.$1);
                              } else {
                                selected.remove(o.$1);
                              }
                            }),
                            title: Text(o.$2,
                                style: const TextStyle(color: AppColors.foreground, fontSize: 13.5)),
                            activeColor: AppColors.primary,
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          )).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      onSave(selected);
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.foreground,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(AppLocalizations.get('save_btn'),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
