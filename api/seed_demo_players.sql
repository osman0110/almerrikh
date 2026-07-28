-- =====================================================================
-- Demo seed data — 5 Al Merrikh SC players with FULL monitoring data:
--   * Player accounts (users) + roster rows (club_players), linked both ways
--   * 7 days of RPE (player_rpe)
--   * 7 days of Hooper Wellness Index (player_hooper_index)
--   * 2 body-composition measurements each, 4 weeks apart (player_body_metrics)
--   * 2 skinfold-based body-fat assessments each, same dates
--     (player_body_composition_assessments — Durnin-Womersley method)
--   * 3 AI physical assessments each — Squat, Single Leg Balance, Jump
--     Landing (assessments) — the MVP's "AI Physical Assessment" module
--
-- HOW TO RUN (production, via phpMyAdmin / cPanel):
--   1. Open phpMyAdmin -> select the app's database -> SQL tab.
--   2. Find your coach account id AND your club's real id:
--        SELECT id, name, email, role FROM users WHERE role = 'club';
--        SELECT club_id, staff_role FROM club_staff WHERE user_id = <that id>;
--        -- (if that returns nothing, the club id is the same as the user id
--        --  above — see resolveClubContext() in api/includes/club_auth.php)
--   3. Replace @club_user_id (any staff id) AND @club_id (the real club id,
--      this is what actually controls what the coach app shows) below.
--   4. Paste the rest of this file and run it. All dates are relative to
--      CURDATE() (today), so the last 7 days of RPE/Hooper always end today
--      no matter when you run this.
--
-- Demo login for all 5 players -> password: Demo@2026
-- (emails: player1..player5.almerrikh@nextkick.demo)
--
-- Safe to re-run: uses fixed ids (demo_p1..demo_p5) and fixed emails,
-- so re-running will fail on duplicate keys instead of creating dupes.
-- To undo, see the DELETE block commented out at the bottom.
-- =====================================================================

-- ⚠️ EDIT THIS: any staff/coach account id at your club (see step 2 above).
-- Data visibility for the coach app is scoped by @club_id below, NOT by this
-- value — a roster/player never belongs to a single coach since a club can
-- have several coaches. club_players.user_id is a required (NOT NULL) column
-- but is no longer used to filter what a coach can see; any valid staff id
-- works here.
SET @club_user_id = NULL;  -- <--- REPLACE NULL WITH ANY STAFF/COACH USER ID AT YOUR CLUB
SET @club_id       = 2;   -- <--- REPLACE 2 WITH YOUR ACTUAL CLUB ID (this is what scopes visibility)
SET @team_id       = NULL;   -- leave NULL unless assigning to a specific team

SET @pwd_hash = '$2y$10$QiLwqVxB2m1T5bFRbWAfWeoEXRPI7.LIPFSob4VHJ9SgF6bSI7DZu'; -- Demo@2026

-- ── 1) Player login accounts ──────────────────────────────────────────
INSERT INTO users (name, email, phone, password_hash, role, account_type, is_active, status, subscription_status)
VALUES
('محمد الأمين حسن',   'player1.almerrikh@nextkick.demo', '249900000001', @pwd_hash, 'player', 'player', 1, 'active', 'active'),
('عثمان جعفر النور',   'player2.almerrikh@nextkick.demo', '249900000002', @pwd_hash, 'player', 'player', 1, 'active', 'active'),
('أحمد بابكر إدريس',   'player3.almerrikh@nextkick.demo', '249900000003', @pwd_hash, 'player', 'player', 1, 'active', 'active'),
('الفاتح عوض الكريم',  'player4.almerrikh@nextkick.demo', '249900000004', @pwd_hash, 'player', 'player', 1, 'active', 'active'),
('صديق محمد طه',       'player5.almerrikh@nextkick.demo', '249900000005', @pwd_hash, 'player', 'player', 1, 'active', 'active');

SET @u1 = (SELECT id FROM users WHERE email = 'player1.almerrikh@nextkick.demo');
SET @u2 = (SELECT id FROM users WHERE email = 'player2.almerrikh@nextkick.demo');
SET @u3 = (SELECT id FROM users WHERE email = 'player3.almerrikh@nextkick.demo');
SET @u4 = (SELECT id FROM users WHERE email = 'player4.almerrikh@nextkick.demo');
SET @u5 = (SELECT id FROM users WHERE email = 'player5.almerrikh@nextkick.demo');

-- ── 2) Roster rows (owned by the coach), linked to the accounts above ──
INSERT INTO club_players
  (id, user_id, name, position, team_name, category, dominant_foot, height_cm, weight_kg,
   number, date_of_birth, nationality, status, player_type, linked_user_id, club_id, team_id, is_active)
VALUES
('demo_p1', @club_user_id, 'محمد الأمين حسن',  'مدافع',     'الفريق الأول', 'senior', 'right', 182, 78, '4', '1999-03-12', 'سوداني', 'active', 'club', @u1, @club_id, @team_id, 1),
('demo_p2', @club_user_id, 'عثمان جعفر النور',  'وسط',       'الفريق الأول', 'senior', 'left',  176, 71, '8', '2001-07-22', 'سوداني', 'active', 'club', @u2, @club_id, @team_id, 1),
('demo_p3', @club_user_id, 'أحمد بابكر إدريس',  'مهاجم',     'الفريق الأول', 'senior', 'right', 179, 74, '9', '2002-01-05', 'سوداني', 'active', 'club', @u3, @club_id, @team_id, 1),
('demo_p4', @club_user_id, 'الفاتح عوض الكريم', 'حارس مرمى', 'الفريق الأول', 'senior', 'right', 188, 85, '1', '1997-11-30', 'سوداني', 'active', 'club', @u4, @club_id, @team_id, 1),
('demo_p5', @club_user_id, 'صديق محمد طه',      'مدافع',     'الفريق الأول', 'senior', 'left',  180, 76, '5', '2000-05-18', 'سوداني', 'active', 'club', @u5, @club_id, @team_id, 1);

UPDATE users SET linked_player_id = 'demo_p1' WHERE id = @u1;
UPDATE users SET linked_player_id = 'demo_p2' WHERE id = @u2;
UPDATE users SET linked_player_id = 'demo_p3' WHERE id = @u3;
UPDATE users SET linked_player_id = 'demo_p4' WHERE id = @u4;
UPDATE users SET linked_player_id = 'demo_p5' WHERE id = @u5;

-- ── 3) RPE — 7 days, one post-session entry per day per player ─────────
-- training_load = rpe_score * duration_minutes
INSERT INTO player_rpe
  (user_id, session_type, rpe_type, rpe_score, duration_minutes, training_load,
   pain_reported, difficulty, mood_after, notes, completed_full_session, linked_player_id, club_id, recorded_by, submitted_at)
VALUES
-- Player 1 — مدافع، حمل مستقر
(@u1,'training','post',6.0,80,480.0,0,'good',4,NULL,1,'demo_p1',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 6 DAY) + INTERVAL 20 HOUR)),
(@u1,'training','post',6.5,85,552.5,0,'good',4,NULL,1,'demo_p1',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 5 DAY) + INTERVAL 20 HOUR)),
(@u1,'training','post',5.5,70,385.0,0,'easy',5,NULL,1,'demo_p1',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 4 DAY) + INTERVAL 20 HOUR)),
(@u1,'training','post',7.0,90,630.0,0,'hard',3,NULL,1,'demo_p1',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 20 HOUR)),
(@u1,'match',   'post',7.5,95,712.5,0,'hard',3,NULL,1,'demo_p1',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 20 HOUR)),
(@u1,'training','post',6.0,75,450.0,0,'good',4,NULL,1,'demo_p1',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 1 DAY) + INTERVAL 20 HOUR)),
(@u1,'training','post',5.5,70,385.0,0,'good',4,NULL,1,'demo_p1',@club_id,'self',(CURDATE() + INTERVAL 20 HOUR)),

-- Player 2 — وسط، حمل تدريبي مرتفع ومؤشرات إرهاق تصاعدية (لاختبار تنبيه الإصابة)
(@u2,'training','post',6.5,90,585.0,0,'good',4,NULL,1,'demo_p2',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 6 DAY) + INTERVAL 20 HOUR)),
(@u2,'training','post',7.0,95,665.0,0,'hard',3,NULL,1,'demo_p2',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 5 DAY) + INTERVAL 20 HOUR)),
(@u2,'training','post',7.5,95,712.5,1,'hard',3,'شعور بشد خفيف في الفخذ',1,'demo_p2',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 4 DAY) + INTERVAL 20 HOUR)),
(@u2,'match',   'post',8.0,100,800.0,1,'hard',2,'ألم خفيف مستمر',1,'demo_p2',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 20 HOUR)),
(@u2,'training','post',8.5,100,850.0,1,'too_hard',2,'الألم زاد قليلاً',0,'demo_p2',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 20 HOUR)),
(@u2,'training','post',7.0,80,560.0,0,'hard',3,NULL,1,'demo_p2',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 1 DAY) + INTERVAL 20 HOUR)),
(@u2,'training','post',6.5,75,487.5,0,'good',3,NULL,1,'demo_p2',@club_id,'self',(CURDATE() + INTERVAL 20 HOUR)),

-- Player 3 — مهاجم، تعافي جيد
(@u3,'training','post',6.0,75,450.0,0,'good',4,NULL,1,'demo_p3',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 6 DAY) + INTERVAL 20 HOUR)),
(@u3,'training','post',6.5,80,520.0,0,'good',5,NULL,1,'demo_p3',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 5 DAY) + INTERVAL 20 HOUR)),
(@u3,'training','post',5.5,70,385.0,0,'easy',5,NULL,1,'demo_p3',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 4 DAY) + INTERVAL 20 HOUR)),
(@u3,'match',   'post',7.0,85,595.0,0,'good',4,NULL,1,'demo_p3',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 20 HOUR)),
(@u3,'training','post',6.5,80,520.0,0,'good',4,NULL,1,'demo_p3',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 20 HOUR)),
(@u3,'training','post',6.0,75,450.0,0,'good',5,NULL,1,'demo_p3',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 1 DAY) + INTERVAL 20 HOUR)),
(@u3,'training','post',5.5,70,385.0,0,'easy',5,NULL,1,'demo_p3',@club_id,'self',(CURDATE() + INTERVAL 20 HOUR)),

-- Player 4 — حارس مرمى، حمل تدريبي أخف
(@u4,'training','post',4.5,60,270.0,0,'good',4,NULL,1,'demo_p4',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 6 DAY) + INTERVAL 20 HOUR)),
(@u4,'training','post',4.0,55,220.0,0,'easy',5,NULL,1,'demo_p4',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 5 DAY) + INTERVAL 20 HOUR)),
(@u4,'training','post',4.5,60,270.0,0,'good',4,NULL,1,'demo_p4',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 4 DAY) + INTERVAL 20 HOUR)),
(@u4,'match',   'post',5.0,65,325.0,0,'good',4,NULL,1,'demo_p4',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 20 HOUR)),
(@u4,'training','post',5.5,70,385.0,0,'good',4,NULL,1,'demo_p4',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 20 HOUR)),
(@u4,'training','post',4.0,55,220.0,0,'easy',5,NULL,1,'demo_p4',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 1 DAY) + INTERVAL 20 HOUR)),
(@u4,'training','post',4.5,60,270.0,0,'good',4,NULL,1,'demo_p4',@club_id,'self',(CURDATE() + INTERVAL 20 HOUR)),

-- Player 5 — مدافع، حادثة ألم بسيطة يوم واحد
(@u5,'training','post',6.0,80,480.0,0,'good',4,NULL,1,'demo_p5',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 6 DAY) + INTERVAL 20 HOUR)),
(@u5,'training','post',6.5,85,552.5,0,'good',3,NULL,1,'demo_p5',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 5 DAY) + INTERVAL 20 HOUR)),
(@u5,'match',   'post',7.5,90,675.0,1,'hard',3,'ألم خفيف في الركبة',1,'demo_p5',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 4 DAY) + INTERVAL 20 HOUR)),
(@u5,'training','post',6.0,75,450.0,0,'good',4,NULL,1,'demo_p5',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 20 HOUR)),
(@u5,'training','post',5.5,70,385.0,0,'good',4,NULL,1,'demo_p5',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 20 HOUR)),
(@u5,'training','post',5.0,65,325.0,0,'easy',5,NULL,1,'demo_p5',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 1 DAY) + INTERVAL 20 HOUR)),
(@u5,'training','post',5.5,70,385.0,0,'good',4,NULL,1,'demo_p5',@club_id,'self',(CURDATE() + INTERVAL 20 HOUR));

-- ── 4) Hooper Wellness Index — 7 days, one morning entry per day per player
-- hooper_score = sleep_quality + fatigue + stress + muscle_soreness (4–28)
INSERT INTO player_hooper_index
  (user_id, sleep_quality, fatigue, stress, muscle_soreness, sleep_hours, hooper_score,
   pain_today, pain_location, mood, notes, linked_player_id, club_id, recorded_by, submitted_at)
VALUES
-- Player 1 — طبيعي/متوسط
(@u1,6,3,3,3,7.5,15,0,NULL,5,NULL,'demo_p1',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 6 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u1,6,3,2,3,7.0,14,0,NULL,5,NULL,'demo_p1',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 5 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u1,7,2,2,2,8.0,13,0,NULL,6,NULL,'demo_p1',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 4 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u1,6,3,3,4,7.0,16,0,NULL,4,NULL,'demo_p1',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u1,5,4,3,4,6.5,16,0,NULL,4,NULL,'demo_p1',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u1,6,3,3,3,7.0,15,0,NULL,5,NULL,'demo_p1',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 1 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u1,7,2,2,3,7.5,14,0,NULL,6,NULL,'demo_p1',@club_id,'self',(CURDATE() + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),

-- Player 2 — تدهور تدريجي في الحيوية (منطقة خطر إصابة)
(@u2,6,3,3,3,7.0,15,0,NULL,5,NULL,'demo_p2',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 6 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u2,5,4,4,4,6.5,17,0,NULL,4,NULL,'demo_p2',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 5 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u2,4,5,4,5,6.0,18,1,'الفخذ الأيمن',3,'إرهاق تراكمي',  'demo_p2',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 4 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u2,4,6,5,5,5.5,20,1,'الفخذ الأيمن',2,'ألم مستمر',       'demo_p2',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u2,3,6,5,6,5.0,20,1,'الفخذ الأيمن',2,'يحتاج راحة',      'demo_p2',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u2,5,5,4,5,6.0,19,0,NULL,3,NULL,'demo_p2',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 1 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u2,5,5,4,4,6.5,18,0,NULL,3,NULL,'demo_p2',@club_id,'self',(CURDATE() + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),

-- Player 3 — تعافي جيد باستمرار
(@u3,7,2,2,2,8.0,13,0,NULL,6,NULL,'demo_p3',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 6 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u3,7,2,3,2,7.5,14,0,NULL,6,NULL,'demo_p3',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 5 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u3,6,3,2,3,7.0,14,0,NULL,5,NULL,'demo_p3',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 4 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u3,7,2,2,2,8.0,13,0,NULL,6,NULL,'demo_p3',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u3,6,3,3,3,7.0,15,0,NULL,5,NULL,'demo_p3',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u3,7,2,2,2,7.5,13,0,NULL,6,NULL,'demo_p3',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 1 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u3,7,2,2,3,8.0,14,0,NULL,6,NULL,'demo_p3',@club_id,'self',(CURDATE() + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),

-- Player 4 — حارس مرمى، ثابت
(@u4,6,3,3,3,7.0,15,0,NULL,5,NULL,'demo_p4',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 6 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u4,6,3,2,3,7.0,14,0,NULL,5,NULL,'demo_p4',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 5 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u4,7,2,2,2,7.5,13,0,NULL,6,NULL,'demo_p4',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 4 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u4,6,3,3,3,7.0,15,0,NULL,5,NULL,'demo_p4',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u4,6,3,3,4,6.5,16,0,NULL,4,NULL,'demo_p4',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u4,7,2,2,2,7.5,13,0,NULL,6,NULL,'demo_p4',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 1 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u4,6,3,2,3,7.0,14,0,NULL,5,NULL,'demo_p4',@club_id,'self',(CURDATE() + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),

-- Player 5 — إصابة بسيطة يوم واحد ثم تعافي
(@u5,6,3,3,3,7.0,15,0,NULL,5,NULL,'demo_p5',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 6 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u5,5,4,3,4,6.5,16,0,NULL,4,NULL,'demo_p5',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 5 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u5,5,4,4,5,6.0,18,1,'الركبة اليسرى',3,'ألم بعد المباراة','demo_p5',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 4 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u5,6,3,3,4,7.0,16,0,NULL,4,NULL,'demo_p5',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u5,6,3,2,3,7.5,14,0,NULL,5,NULL,'demo_p5',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u5,7,2,2,3,7.5,14,0,NULL,6,NULL,'demo_p5',@club_id,'self',(DATE_SUB(CURDATE(), INTERVAL 1 DAY) + INTERVAL 7 HOUR + INTERVAL 30 MINUTE)),
(@u5,6,3,2,3,7.0,14,0,NULL,5,NULL,'demo_p5',@club_id,'self',(CURDATE() + INTERVAL 7 HOUR + INTERVAL 30 MINUTE));

-- ── 5) Body composition — 2 measurements per player, 4 weeks apart ─────
INSERT INTO player_body_metrics
  (user_id, weight_kg, height_cm, body_fat_percent, bmi, fat_mass_kg, lean_mass_kg, waist_cm,
   measurement_method, measured_by, specialist_notes, linked_player_id, recorded_by, measured_at)
VALUES
(@u1,79.0,182,13.2,23.85,10.43,68.57,83.5,'bia','الجهاز الطبي','قياس دوري',   'demo_p1','coach',(DATE_SUB(CURDATE(), INTERVAL 30 DAY) + INTERVAL 9 HOUR)),
(@u1,78.0,182,12.5,23.55,9.75, 68.25,82.0,'bia','الجهاز الطبي','تحسن طفيف',   'demo_p1','coach',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 9 HOUR)),

(@u2,72.5,176,11.5,23.41,8.34, 64.16,79.0,'bia','الجهاز الطبي','قياس دوري',   'demo_p2','coach',(DATE_SUB(CURDATE(), INTERVAL 30 DAY) + INTERVAL 9 HOUR)),
(@u2,71.0,176,10.8,22.92,7.67, 63.33,78.0,'bia','الجهاز الطبي','فقدان وزن طفيف مع إرهاق تدريبي','demo_p2','coach',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 9 HOUR)),

(@u3,73.0,179,12.0,22.78,8.76, 64.24,79.0,'bia','الجهاز الطبي','قياس دوري',   'demo_p3','coach',(DATE_SUB(CURDATE(), INTERVAL 30 DAY) + INTERVAL 9 HOUR)),
(@u3,74.0,179,11.2,23.09,8.29, 65.71,80.0,'bia','الجهاز الطبي','زيادة كتلة عضلية','demo_p3','coach',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 9 HOUR)),

(@u4,86.0,188,15.0,24.34,12.90,73.10,90.0,'bia','الجهاز الطبي','قياس دوري',   'demo_p4','coach',(DATE_SUB(CURDATE(), INTERVAL 30 DAY) + INTERVAL 9 HOUR)),
(@u4,85.0,188,14.0,24.05,11.90,73.10,88.0,'bia','الجهاز الطبي','تحسن في النسبة الدهنية','demo_p4','coach',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 9 HOUR)),

(@u5,77.0,180,13.0,23.77,10.01,66.99,83.0,'bia','الجهاز الطبي','قياس دوري',   'demo_p5','coach',(DATE_SUB(CURDATE(), INTERVAL 30 DAY) + INTERVAL 9 HOUR)),
(@u5,76.0,180,12.0,23.46,9.12, 66.88,81.0,'bia','الجهاز الطبي','تحسن طفيف',   'demo_p5','coach',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 9 HOUR));

-- ── 6) Body-fat assessments — skinfold-based (Durnin-Womersley), 2 per
-- player, same dates as the body_metrics rows above. All 5 players fall in
-- the 20-29 age band as of these dates, so calculation_formula_code is the
-- same for everyone. Skinfold sums were chosen so the formula
-- (BF% = 27.775 * LOG10(sum) - 27.203) reproduces the exact body_fat_percent
-- already seeded in player_body_metrics above, so both tables agree.
INSERT INTO player_body_composition_assessments
  (id, user_id, club_id, linked_player_id, recorded_by, team_name, position,
   assessment_date, assessment_time, assessment_type, height_cm, weight_kg, age_at_assessment,
   biceps_attempt_1_mm, biceps_attempt_2_mm, biceps_attempt_3_mm, biceps_mm,
   triceps_attempt_1_mm, triceps_attempt_2_mm, triceps_attempt_3_mm, triceps_mm,
   subscapular_attempt_1_mm, subscapular_attempt_2_mm, subscapular_attempt_3_mm, subscapular_mm,
   suprailiac_attempt_1_mm, suprailiac_attempt_2_mm, suprailiac_attempt_3_mm, suprailiac_mm,
   skinfold_sum_mm, calculation_formula_code, calculation_age_group,
   body_fat_percentage, fat_mass_kg, fat_free_mass_kg, bmi, notes, assessed_by)
VALUES
-- Player 1 — مدافع
('demo_bc_p1_1',@u1,@club_id,'demo_p1','coach','الفريق الأول','مدافع',DATE_SUB(CURDATE(), INTERVAL 30 DAY),'09:00','initial',182,79.0,27,
 4.3,4.3,4.3,4.3, 8.5,8.5,8.5,8.5, 8.0,8.0,8.0,8.0, 7.7,7.7,7.7,7.7,
 28.5,'age_20_29','20-29', 13.2,10.43,68.57,23.85,'قياس دوري','الجهاز الطبي'),
('demo_bc_p1_2',@u1,@club_id,'demo_p1','coach','الفريق الأول','مدافع',DATE_SUB(CURDATE(), INTERVAL 2 DAY),'09:00','periodic',182,78.0,27,
 4.0,4.0,4.0,4.0, 8.1,8.1,8.1,8.1, 7.5,7.5,7.5,7.5, 7.3,7.3,7.3,7.3,
 26.9,'age_20_29','20-29', 12.5,9.75,68.25,23.55,'تحسن طفيف','الجهاز الطبي'),

-- Player 2 — وسط
('demo_bc_p2_1',@u2,@club_id,'demo_p2','coach','الفريق الأول','وسط',DATE_SUB(CURDATE(), INTERVAL 30 DAY),'09:00','initial',176,72.5,24,
 3.7,3.7,3.7,3.7, 7.4,7.4,7.4,7.4, 6.9,6.9,6.9,6.9, 6.7,6.7,6.7,6.7,
 24.7,'age_20_29','20-29', 11.5,8.34,64.16,23.41,'قياس دوري','الجهاز الطبي'),
('demo_bc_p2_2',@u2,@club_id,'demo_p2','coach','الفريق الأول','وسط',DATE_SUB(CURDATE(), INTERVAL 2 DAY),'09:00','periodic',176,71.0,24,
 3.5,3.5,3.5,3.5, 7.0,7.0,7.0,7.0, 6.5,6.5,6.5,6.5, 6.3,6.3,6.3,6.3,
 23.3,'age_20_29','20-29', 10.8,7.67,63.33,22.92,'فقدان وزن طفيف مع إرهاق تدريبي','الجهاز الطبي'),

-- Player 3 — مهاجم
('demo_bc_p3_1',@u3,@club_id,'demo_p3','coach','الفريق الأول','مهاجم',DATE_SUB(CURDATE(), INTERVAL 30 DAY),'09:00','initial',179,73.0,24,
 3.9,3.9,3.9,3.9, 7.7,7.7,7.7,7.7, 7.2,7.2,7.2,7.2, 7.0,7.0,7.0,7.0,
 25.8,'age_20_29','20-29', 12.0,8.76,64.24,22.78,'قياس دوري','الجهاز الطبي'),
('demo_bc_p3_2',@u3,@club_id,'demo_p3','coach','الفريق الأول','مهاجم',DATE_SUB(CURDATE(), INTERVAL 2 DAY),'09:00','periodic',179,74.0,24,
 3.6,3.6,3.6,3.6, 7.2,7.2,7.2,7.2, 6.8,6.8,6.8,6.8, 6.5,6.5,6.5,6.5,
 24.1,'age_20_29','20-29', 11.2,8.29,65.71,23.09,'زيادة كتلة عضلية','الجهاز الطبي'),

-- Player 4 — حارس مرمى
('demo_bc_p4_1',@u4,@club_id,'demo_p4','coach','الفريق الأول','حارس مرمى',DATE_SUB(CURDATE(), INTERVAL 30 DAY),'09:00','initial',188,86.0,28,
 5.0,5.0,5.0,5.0, 9.9,9.9,9.9,9.9, 9.3,9.3,9.3,9.3, 8.9,8.9,8.9,8.9,
 33.1,'age_20_29','20-29', 15.0,12.90,73.10,24.34,'قياس دوري','الجهاز الطبي'),
('demo_bc_p4_2',@u4,@club_id,'demo_p4','coach','الفريق الأول','حارس مرمى',DATE_SUB(CURDATE(), INTERVAL 2 DAY),'09:00','periodic',188,85.0,28,
 4.6,4.6,4.6,4.6, 9.1,9.1,9.1,9.1, 8.6,8.6,8.6,8.6, 8.2,8.2,8.2,8.2,
 30.5,'age_20_29','20-29', 14.0,11.90,73.10,24.05,'تحسن في النسبة الدهنية','الجهاز الطبي'),

-- Player 5 — مدافع
('demo_bc_p5_1',@u5,@club_id,'demo_p5','coach','الفريق الأول','مدافع',DATE_SUB(CURDATE(), INTERVAL 30 DAY),'09:00','initial',180,77.0,26,
 4.2,4.2,4.2,4.2, 8.4,8.4,8.4,8.4, 7.8,7.8,7.8,7.8, 7.6,7.6,7.6,7.6,
 28.0,'age_20_29','20-29', 13.0,10.01,66.99,23.77,'قياس دوري','الجهاز الطبي'),
('demo_bc_p5_2',@u5,@club_id,'demo_p5','coach','الفريق الأول','مدافع',DATE_SUB(CURDATE(), INTERVAL 2 DAY),'09:00','periodic',180,76.0,26,
 3.9,3.9,3.9,3.9, 7.7,7.7,7.7,7.7, 7.2,7.2,7.2,7.2, 7.0,7.0,7.0,7.0,
 25.8,'age_20_29','20-29', 12.0,9.12,66.88,23.46,'تحسن طفيف','الجهاز الطبي');

-- ── 7) AI Physical Assessments — Squat, Single Leg Balance, Jump Landing.
-- One of each MVP test per player, scores consistent with each player's
-- wellness/RPE narrative above (e.g. demo_p2's fatigue trend shows up as
-- lower stability/symmetry in their latest tests).
INSERT INTO assessments
  (id, user_id, club_id, player_id, player_name, type,
   overall_score, movement_quality_score, stability_score, symmetry_score, control_score, quality_score,
   issues_json, tips_json, drills_json, angle_metrics_json, notes,
   pain_reported, difficulty, attempt_number, is_valid, status, created_at)
VALUES
-- Player 1 — محمد الأمين حسن، مدافع، ثبات جيد
('demo_a_p1_squat',@u1,@club_id,'demo_p1','محمد الأمين حسن','squat',
 86,85,88,87,84,86,
 '["ميل طفيف للركبة للداخل عند العمق الكامل"]','["حافظ على محاذاة الركبة مع أصابع القدم"]','["تمارين تقوية العضلة المقربة"]',
 '{"knee_flexion_deg":118,"hip_flexion_deg":95,"trunk_lean_deg":8}','أداء ثابت',
 0,'good',1,1,'approved',(DATE_SUB(CURDATE(), INTERVAL 6 DAY) + INTERVAL 16 HOUR)),
('demo_a_p1_balance',@u1,@club_id,'demo_p1','محمد الأمين حسن','singleLegBalance',
 82,81,84,83,80,82,
 '["تذبذب خفيف في الكاحل بعد 20 ثانية"]','["تمارين توازن على سطح غير مستقر"]','["وقوف على رجل واحد بعينين مغلقتين"]',
 '{"sway_index":4.2,"hold_time_sec":28}','توازن جيد إجمالاً',
 0,'good',1,1,'approved',(DATE_SUB(CURDATE(), INTERVAL 4 DAY) + INTERVAL 16 HOUR)),
('demo_a_p1_jump',@u1,@club_id,'demo_p1','محمد الأمين حسن','jumpLanding',
 89,88,90,89,87,89,
 '[]','["حافظ على هذا المستوى من التحكم عند الهبوط"]','[]',
 '{"knee_valgus_deg":3,"landing_impact_g":2.1}','هبوط متحكم به وممتاز',
 0,'easy',1,1,'pending_review',(DATE_SUB(CURDATE(), INTERVAL 1 DAY) + INTERVAL 16 HOUR)),

-- Player 2 — عثمان جعفر النور، وسط، إرهاق تراكمي ينعكس على الثبات والتناظر
('demo_a_p2_squat',@u2,@club_id,'demo_p2','عثمان جعفر النور','squat',
 79,80,78,79,78,79,
 '["انحناء طفيف للجذع للأمام"]','["تقوية عضلات الجذع للحفاظ على الوضعية"]','["تمارين بلانك وتقوية أسفل الظهر"]',
 '{"knee_flexion_deg":110,"hip_flexion_deg":88,"trunk_lean_deg":14}','قياس أساسي قبل بداية الإرهاق',
 0,'good',1,1,'approved',(DATE_SUB(CURDATE(), INTERVAL 6 DAY) + INTERVAL 16 HOUR)),
('demo_a_p2_balance',@u2,@club_id,'demo_p2','عثمان جعفر النور','singleLegBalance',
 68,70,64,66,69,68,
 '["تذبذب واضح في الورك","صعوبة في الحفاظ على الثبات بعد 10 ثوانٍ"]','["تقليل الحمل التدريبي مؤقتاً","تمارين استقرار الورك"]','["تمارين توازن تدريجية منخفضة الشدة"]',
 '{"sway_index":8.7,"hold_time_sec":11}','ثبات ضعيف يتوافق مع مؤشر الإرهاق المرتفع هذا الأسبوع',
 1,'hard',1,1,'approved',(DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 16 HOUR)),
('demo_a_p2_jump',@u2,@club_id,'demo_p2','عثمان جعفر النور','jumpLanding',
 65,66,62,64,67,65,
 '["امتصاص صدمة ضعيف عند الهبوط","عدم تناظر واضح بين الرجلين"]','["يُنصح بجلسة تعافي قبل التقييم التالي","مراجعة الطبيب/أخصائي العلاج الطبيعي"]','["تمارين هبوط منخفضة الشدة تحت إشراف"]',
 '{"knee_valgus_deg":11,"landing_impact_g":3.8}','نتيجة تستدعي متابعة — تزامنت مع أعلى قراءة إرهاق',
 1,'too_hard',1,1,'pending_review',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 16 HOUR)),

-- Player 3 — أحمد بابكر إدريس، مهاجم، تعافي جيد باستمرار
('demo_a_p3_squat',@u3,@club_id,'demo_p3','أحمد بابكر إدريس','squat',
 92,91,93,92,90,92,
 '[]','["حافظ على الأداء الممتاز"]','[]',
 '{"knee_flexion_deg":122,"hip_flexion_deg":98,"trunk_lean_deg":5}','أداء ممتاز',
 0,'easy',1,1,'approved',(DATE_SUB(CURDATE(), INTERVAL 5 DAY) + INTERVAL 16 HOUR)),
('demo_a_p3_balance',@u3,@club_id,'demo_p3','أحمد بابكر إدريس','singleLegBalance',
 90,89,92,90,88,90,
 '[]','["حافظ على مستوى الثبات الحالي"]','[]',
 '{"sway_index":2.1,"hold_time_sec":30}','ثبات ممتاز',
 0,'easy',1,1,'approved',(DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 16 HOUR)),
('demo_a_p3_jump',@u3,@club_id,'demo_p3','أحمد بابكر إدريس','jumpLanding',
 94,93,95,94,92,94,
 '[]','["جاهز لزيادة شدة تمارين القفز"]','["تمارين قفز بليومترك متقدمة"]',
 '{"knee_valgus_deg":1,"landing_impact_g":1.8}','أفضل نتيجة في هذه الدورة',
 0,'easy',1,1,'pending_review',(DATE_SUB(CURDATE(), INTERVAL 1 DAY) + INTERVAL 16 HOUR)),

-- Player 4 — الفاتح عوض الكريم، حارس مرمى، ثبات وتحكم جيدان يلائمان مركزه
('demo_a_p4_squat',@u4,@club_id,'demo_p4','الفاتح عوض الكريم','squat',
 81,80,83,82,79,81,
 '["محدودية طفيفة في مدى حركة الكاحل"]','["إطالة عضلة السمانة"]','["تمارين مرونة الكاحل"]',
 '{"knee_flexion_deg":112,"hip_flexion_deg":90,"trunk_lean_deg":9}','أداء جيد',
 0,'good',1,1,'approved',(DATE_SUB(CURDATE(), INTERVAL 5 DAY) + INTERVAL 16 HOUR)),
('demo_a_p4_balance',@u4,@club_id,'demo_p4','الفاتح عوض الكريم','singleLegBalance',
 85,84,87,85,83,85,
 '[]','["حافظ على برنامج التوازن الحالي"]','[]',
 '{"sway_index":3.0,"hold_time_sec":29}','توازن ممتاز يلائم متطلبات مركز الحراسة',
 0,'good',1,1,'approved',(DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 16 HOUR)),
('demo_a_p4_jump',@u4,@club_id,'demo_p4','الفاتح عوض الكريم','jumpLanding',
 83,82,85,84,81,83,
 '["زاوية هبوط غير متساوية قليلاً بين الجانبين"]','["تمارين هبوط أحادي الجانب"]','["تمارين قفز جانبية للحارس"]',
 '{"knee_valgus_deg":6,"landing_impact_g":2.6}','جيد مع ملاحظة بسيطة على التناظر',
 0,'good',1,1,'pending_review',(DATE_SUB(CURDATE(), INTERVAL 1 DAY) + INTERVAL 16 HOUR)),

-- Player 5 — صديق محمد طه، مدافع، أثر ألم الركبة الخفيف على نتيجة القفز
('demo_a_p5_squat',@u5,@club_id,'demo_p5','صديق محمد طه','squat',
 84,83,86,85,82,84,
 '[]','["حافظ على الأداء الحالي"]','[]',
 '{"knee_flexion_deg":116,"hip_flexion_deg":93,"trunk_lean_deg":7}','أداء جيد قبل حادثة الألم',
 0,'good',1,1,'approved',(DATE_SUB(CURDATE(), INTERVAL 5 DAY) + INTERVAL 16 HOUR)),
('demo_a_p5_balance',@u5,@club_id,'demo_p5','صديق محمد طه','singleLegBalance',
 77,76,74,75,78,77,
 '["تجنب إضافي للحمل على الركبة اليسرى"]','["تمارين توازن خفيفة حتى زوال الألم"]','["تمارين استقرار الركبة منخفضة الشدة"]',
 '{"sway_index":5.5,"hold_time_sec":22}','تأثر بألم الركبة اليسرى المسجل قبل يومين',
 1,'hard',1,1,'approved',(DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 16 HOUR)),
('demo_a_p5_jump',@u5,@club_id,'demo_p5','صديق محمد طه','jumpLanding',
 71,70,68,70,73,71,
 '["امتصاص صدمة غير كافٍ على الجانب الأيسر","علامات تعويض حركي بسبب الألم"]','["يُنصح بالراحة النسبية ومتابعة الركبة اليسرى","تمارين تقوية تدريجية بعد زوال الألم"]','["لا يُنصح بتمارين قفز إضافية حالياً"]',
 '{"knee_valgus_deg":9,"landing_impact_g":3.2}','نتيجة أقل بسبب ألم الركبة اليسرى — يستدعي متابعة',
 1,'hard',1,1,'pending_review',(DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 16 HOUR));

-- =====================================================================
-- ROLLBACK (uncomment and run to remove everything this script added):
--
-- DELETE FROM assessments WHERE player_id IN ('demo_p1','demo_p2','demo_p3','demo_p4','demo_p5');
-- DELETE FROM player_body_composition_assessments WHERE linked_player_id IN ('demo_p1','demo_p2','demo_p3','demo_p4','demo_p5');
-- DELETE FROM player_body_metrics  WHERE linked_player_id IN ('demo_p1','demo_p2','demo_p3','demo_p4','demo_p5');
-- DELETE FROM player_hooper_index  WHERE linked_player_id IN ('demo_p1','demo_p2','demo_p3','demo_p4','demo_p5');
-- DELETE FROM player_rpe           WHERE linked_player_id IN ('demo_p1','demo_p2','demo_p3','demo_p4','demo_p5');
-- DELETE FROM club_players         WHERE id IN ('demo_p1','demo_p2','demo_p3','demo_p4','demo_p5');
-- DELETE FROM users WHERE email IN (
--   'player1.almerrikh@nextkick.demo','player2.almerrikh@nextkick.demo',
--   'player3.almerrikh@nextkick.demo','player4.almerrikh@nextkick.demo',
--   'player5.almerrikh@nextkick.demo');
-- =====================================================================
