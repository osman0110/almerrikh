# Apple Review — Build 16 package

Prepared 2026-09-15 for the rejection of 1.0 (15): Guideline 5.1.1(v) Account Deletion and
Guideline 2.3.3 iPad screenshots.

## Contents

- `screenshots_ipad_13/` — 12 PNGs, 2064x2752 (13-inch iPad portrait, the size App Store Connect
  currently asks for). Six Arabic + six English: dashboard after sign-in, players roster, player
  profile, team executive report, settings/account, delete-account dialog. Rendered from the real
  app (Flutter web build of this branch at iPad resolution, Chrome device-pixel-ratio 2), not
  marketing mockups. Spot-check on a physical iPad before upload if possible.
- `deletion_success_proof_ar.png` — the "Account deleted" confirmation captured from the real flow.
- `delete-account.html` — updated public deletion page; upload to `nextkick.me/delete-account.html`
  (replaces the copy in `academy/nextkickwebsite/`).
- `ACCOUNT_DELETION_VIDEO_STEPS.md` — recording steps for the reviewer video.
- `capture_ipad_screenshots.js` — puppeteer-core script used to capture the screenshots
  (needs `npm i puppeteer-core`, a `flutter build web --base-href /merr/build/web/` served by WAMP,
  and a local API token).

## Deploy checklist before uploading build 16

1. Upload `api/auth.php` (this branch) to `https://nextkick.me/api/auth.php`.
   Verify: `curl -X POST https://nextkick.me/api/auth.php?action=delete_account` → `{"error":"Unauthorized"}`.
2. Upload `docs/apple_review/delete-account.html` to `https://nextkick.me/delete-account.html`.
3. Create a disposable reviewer account (staff via access code, or a player) and put it in
   App Review Information. Do NOT hand the club-owner demo account to Apple.
4. Trigger the Codemagic `ios-appstore` workflow; the build number floor is 16.
