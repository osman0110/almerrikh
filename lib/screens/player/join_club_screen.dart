import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../storage.dart';

class JoinClubScreen extends StatefulWidget {
  const JoinClubScreen({super.key});

  @override
  State<JoinClubScreen> createState() => _JoinClubScreenState();
}

class _JoinClubScreenState extends State<JoinClubScreen> {
  final _codeCtrl   = TextEditingController();
  bool _shareHistory = true;
  bool _submitting   = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length < 6) {
      _snack('يرجى إدخال كود صالح (6+ أحرف)');
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await ApiService.joinClub(
        inviteCode: code,
        shareHistory: _shareHistory,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        // Update ALL local state immediately — no restart needed
        currentPlayerType = PlayerType.club;
        await OnboardingStore().setPlayerType(PlayerType.club);

        final newLinkedId = res['linked_player_id'] as String?;
        if (newLinkedId != null && newLinkedId.isNotEmpty) {
          await OnboardingStore().setLinkedPlayerId(newLinkedId);
        }
        final clubUserId = res['club_user_id'];
        if (clubUserId != null) {
          final cid = clubUserId is int
              ? clubUserId
              : int.tryParse(clubUserId.toString());
          if (cid != null) await OnboardingStore().setClubUserId(cid);
        }

        _snack(res['message']?.toString() ?? 'تم الانضمام بنجاح ✓');
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          // Replace full stack so dashboard rebuilds with club view
          Navigator.of(context).pushNamedAndRemoveUntil('/player', (_) => false);
        }
      } else {
        _snack(res['error']?.toString() ?? 'كود غير صحيح أو منتهي');
      }
    } catch (_) {
      if (mounted) _snack('حدث خطأ في الاتصال');
    }
    if (mounted) setState(() => _submitting = false);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.foreground, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'الانضمام لنادي',
            style: TextStyle(
                color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 17),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Icon
            Center(
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.sports_soccer_rounded,
                    color: AppColors.primary, size: 36),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'أدخل كود الدعوة من ناديك',
                style: TextStyle(
                    color: AppColors.foreground,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'طلب الكود من المدرب أو الإدارة',
                style: TextStyle(
                    color: AppColors.foreground.withOpacity(0.45), fontSize: 13),
              ),
            ),
            const SizedBox(height: 28),

            // Code input
            TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.foreground,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6),
              decoration: InputDecoration(
                hintText: 'XXXXXXXX',
                hintStyle: TextStyle(
                    color: AppColors.foreground.withOpacity(0.20),
                    fontSize: 24,
                    letterSpacing: 6),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Share history option
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'مشاركة سجل التدريب السابق',
                          style: TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'السماح للنادي برؤية تقييماتك السابقة',
                          style: TextStyle(
                              color: AppColors.foreground.withOpacity(0.45),
                              fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _shareHistory,
                    onChanged: (v) => setState(() => _shareHistory = v),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Text('تأكيد الانضمام',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
