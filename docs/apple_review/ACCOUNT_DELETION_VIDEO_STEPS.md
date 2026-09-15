# خطوات تسجيل فيديو حذف الحساب (App Review — Guideline 5.1.1(v))

سجّل الفيديو على iPhone حقيقي من TestFlight (Build 16 أو أعلى) عبر
الإعدادات ← مركز التحكم ← تسجيل الشاشة. لا تقطع التسجيل بين الخطوات.

## قبل التسجيل

1. تأكد أن `auth.php` المحدّث مرفوع على `https://nextkick.me/api/` (اختبار سريع من أي متصفح أو curl):
   ```
   curl -X POST "https://nextkick.me/api/auth.php?action=delete_account"
   ```
   النتيجة الصحيحة: `{"error":"Unauthorized"}` (401). إذا ظهر `Unknown action` فالملف لم يُرفع بعد.
2. أنشئ حساب مراجعة قابل للحذف (وليس حساب مالك النادي التجريبي):
   * من التطبيق أو لوحة التحكم: أنشئ كود دخول لدور "coach" أو "player" لنادي المريخ.
   * أنشئ المستخدم `applereview+16@…` بكلمة مرور معروفة، أو أضفه مباشرة في قاعدة البيانات
     (`users` + صف في `club_staff` بحالة active).
   * ضع بيانات هذا الحساب في App Review Information ← Sign-in required.
   * بعد أن يحذفه المراجع، أعد إنشاءه قبل أي مراجعة لاحقة.

## خطوات الفيديو

1. **تسجيل الدخول**: افتح التطبيق ← شاشة Sign In ← أدخل البريد وكلمة المرور ← Sign in.
   يظهر الـDashboard الخاص بالنادي.
2. **الوصول إلى خيار الحذف**:
   * حساب طاقم/مدرب: اضغط زر القائمة (☰) أعلى الشاشة ← **الملف الشخصي** ← قسم **الحساب**
     ← **حذف الحساب** (الصف الأحمر أسفل "تسجيل الخروج").
   * حساب لاعب: تبويب **الملف الشخصي** في الأسفل ← **حذف الحساب**.
3. **تأكيد الحذف**: تظهر نافذة "حذف حسابك؟" توضح ما سيُحذف. أدخل كلمة المرور ← اضغط **حذف نهائي**.
   تظهر نافذة "جارٍ حذف الحساب…" لثوانٍ.
4. **نتيجة النجاح**: تظهر نافذة "تم حذف الحساب — تم حذف حسابك وبياناتك الشخصية بشكل نهائي" ← اضغط **حسناً**
   ← يعود التطبيق إلى شاشة تسجيل الدخول.
5. (اختياري لكن مفيد) حاول تسجيل الدخول بنفس البيانات — تظهر رسالة "Invalid email or password"،
   ما يثبت أن الحذف فعلي وليس تعطيلًا.

## ملاحظة للرد على Apple (Resolution Center)

> Build 16 adds an in-app "Delete account" option (Profile → Account → Delete account for staff,
> Profile tab → Delete account for players). It permanently deletes the login, profile, devices,
> notifications and self-submitted data on our servers after password confirmation, then shows a
> success confirmation and signs the user out. A demo account that can be deleted is provided in
> App Review Information; the attached video shows the full flow.
