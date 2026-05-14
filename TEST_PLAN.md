# MVP Bug Fixes - Test Plan

## Fixes Applied (Phase 1 + 2)

### CRITICAL FIXES
1. ✅ Removed Firestore benchmark from RootGate startup → **App now loads fast**
2. ✅ Fixed SessionFormPage lifecycle safety → **No more setState after dispose crashes**
3. ✅ Fixed ClubSettingsPage logout crash → **Logout now safe**
4. ✅ Added RootGate error logging → **Debugging enabled**
5. ✅ Added SessionListPage error handling → **No more blank screens on errors**
6. ✅ Optimized SessionListPage timing → **Performance improved**

---

## TEST FLOWS

### Test 1: App Startup Speed
**Expected Result:** App loads dashboard in <2 seconds
- [ ] Start app
- [ ] Measure time from splash to dashboard
- [ ] Should NOT see 30-second loading screen

**Logs to Watch:**
```
[RootGate] Queuing Firestore benchmark... (should be non-blocking)
[Main] App initialization complete in <1000ms
```

---

### Test 2: Add Player Flow
**Expected Result:** Player saves successfully, appears in list
- [ ] Navigate to Club → Players
- [ ] Click Add button
- [ ] Fill form: Name, Position, Team, Number
- [ ] Click Save
- [ ] See success SnackBar: "Player added successfully"
- [ ] Return to list and see new player immediately

**Logs to Watch:**
```
[AddPlayer] Save pressed
[AddPlayer] addPlayer start
[ClubService.addPlayer] Starting - name: <name>
[ClubService.addPlayer] Player doc created: <id>
[AddPlayer] addPlayer end, playerId: <id>
```

---

### Test 3: Session List Error Handling
**Expected Result:** Error shown instead of blank screen
- [ ] Navigate to Club → Sessions
- [ ] Simulate Firestore error (toggle airplane mode, network down, etc.)
- [ ] Page should show error message with retry button
- [ ] Click Retry, error should clear when network recovers

**Logs to Watch:**
```
[Sessions] Stream error: <error details>
```

---

### Test 4: Session Form Lifecycle Safety
**Expected Result:** No crashes when navigating away during load
- [ ] Navigate to Club → Sessions → New
- [ ] Quickly navigate back before form loads
- [ ] Check console for no errors
- [ ] No "setState called after dispose" warnings

---

### Test 5: Club Settings Logout
**Expected Result:** Logout works without crash
- [ ] Navigate to Club → Settings
- [ ] Click Sign Out
- [ ] Should return to auth page smoothly
- [ ] No lifecycle errors in console

---

### Test 6: Player Profile Quick Navigation
**Expected Result:** No crashes when navigating away
- [ ] Open a player profile
- [ ] Quickly navigate away while data loads
- [ ] No "setState called after dispose" errors

---

## Bug Severity Legend
- 🔴 CRITICAL: App crashes, data loss, impossible to use
- 🟠 HIGH: Feature broken, user gets stuck
- 🟡 MEDIUM: Workaround exists, but poor UX
- 🟢 LOW: Minor issue, cosmetic

---

## Success Criteria
✅ All 6 test flows complete without errors or crashes
✅ No "setState after dispose" warnings in console
✅ App startup <2 seconds
✅ All player operations save successfully
✅ Error states handled gracefully

---

## Known Remaining Issues (Phase 3 + 4 - Lower Priority)
- Dashboard stats loading (BUG #11)
- Player profile note optimization (BUG #12)
- Auth page animation timing (BUG #13)
- Player list caching (BUG #14)
- Session form team validation (BUG #15)
