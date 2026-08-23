# CLAUDE.md

## Project Overview
 is a Flutter + Firebase AI football performance platform focused on:

* football physical assessment
* biomechanics
* AI pose detection
* movement quality analysis
* player tracking
* club management
* physical coach workflow

Current target:
Build a stable MVP demo for a football club physical coach.

Current client/demo target:
Al Merrikh SC (Sudan)

---

# MVP Scope (STRICT)

Only focus on these modules:

1. Club Dashboard
2. Player Management
3. Player Profiles
4. Session Management
5. AI Physical Assessment
6. Reports

ONLY support these physical tests for MVP:

* Squat Assessment
* Single Leg Balance
* Jump Landing Assessment

Do NOT add extra assessment types.

---

# Product Roadmap (Post-MVP — Not Current Scope)

The items below describe the long-term product vision. They are NOT part of the current MVP and must not be implemented unless explicitly requested. Current work is still governed by "MVP Scope (STRICT)" above.

## 1. Physical Performance (extend existing)

Current foundation is solid:

* physical tests / FMS
* body composition
* RPE and Hooper Index
* weekly loads
* sessions and attendance
* readiness and risk flags

Remaining work: link attendance, participation duration, injury, and rest into actual training-load calculation.

## 2. Medical Module

A single "injury notes" field is not enough. Needs a full injury record:

* injury date, location, type, severity
* doctor diagnosis, exams, attachments
* player status: available / limited / unavailable / rehab / graduated return
* treatment and rehab plan
* Return-to-Play stages with pass criteria per stage
* expected vs. actual return date
* full audit/timeline of updates

Coaches must NOT see sensitive medical detail — only participation status and restrictions.

## 3. Physiotherapy & Massage Module

Independent module linked to the medical file:

* session booking
* body-map area selection
* session reason: recovery, pain, muscle tightness, pre/post-match
* treatment type, duration, intensity
* contraindications and medical alerts
* specialist notes and player response
* recommendation: rest / modified training / doctor follow-up / another session
* daily schedule showing therapist/room workload

## 4. Nutrition Module

* allergy and dietary restriction profile
* daily calorie/protein/carb/fluid targets
* separate plans for training day, match day, travel, rest day
* weight, body-fat, muscle-mass goals
* hydration plan (before/during/after training)
* supplements requiring doctor + nutritionist sign-off
* daily compliance logging and alerts
* linked to body composition, load, sleep, and injuries

## 5. Unified Daily Workflow

Player questionnaire → readiness check → alert to physical coach/medical staff → treatment/massage/nutrition intervention → participation status decision → log load & post-training response.

Coach view is restricted to: fully available / modified training / unavailable, allowed participation duration, and general restrictions — never medical diagnosis or confidential treatment notes (unless explicitly granted access).

## 6. Roles & Permissions

* System admin
* Performance manager
* Physical coach
* Doctor
* Physiotherapist
* Massage specialist
* Nutritionist
* Coach (readiness-status view only)
* Player (submits questionnaires, views own plan)

## 7. Execution Order (roadmap priority)

1. Fix club data isolation and permissions.
2. Complete attendance, actual exposure time, and load tracking.
3. Build injury/rehab/return-to-play file.
4. Build physiotherapy & massage schedule.
5. Build nutrition, hydration, and supplements module.
6. Build a unified daily readiness & intervention dashboard.
7. Later: GPS and wearable device integration.

---

# Current Development Priority

Current focus:

1. Stability
2. Fast workflow
3. Demo readiness
4. Accurate movement scoring
5. Clean UI

NOT priorities:

* advanced architecture
* reusable UI systems
* over-engineering
* micro-optimizations
* feature expansion

---

# Critical Development Rules

## DO NOT:

* rebuild app architecture
* rewrite unrelated modules
* refactor working code unnecessarily
* create unnecessary abstractions
* create reusable UI systems unless requested
* generate large unrelated code blocks
* redesign the entire app
* change Firebase structure unless necessary
* introduce complex state management unless required

## DO:

* keep code modular but simple
* prefer inline widgets for MVP speed
* make minimal changes
* preserve existing working services
* preserve pose detection pipeline
* preserve biomechanics logic
* preserve existing navigation unless required

---

# Token Optimization Rules

IMPORTANT:

* Be concise.
* Show only modified code blocks.
* Do NOT rewrite full files unless necessary.
* Avoid long explanations.
* Avoid repeating existing code.
* Prefer minimal patches.
* Ask before generating large files.
* Focus only on the requested phase/task.

When fixing bugs:

1. identify root cause
2. patch minimally
3. avoid broad refactors

---

# UI / UX Direction

Theme:

* dark premium UI
* Al Merrikh red accents
* white typography
* subtle gold highlights
* football sports-science aesthetic

UI goals:

* clean
* modern
* professional
* fast
* demo-ready

Avoid:

* generic fitness app look
* childish UI
* excessive animations
* cluttered dashboards

---

# MVP Workflow

Main workflow:

Login
→ Club Dashboard
→ Players
→ Player Profile
→ Start AI Assessment
→ Camera
→ Results
→ Save

Keep this flow extremely fast.

---

# AI Assessment Rules

Current MVP tests:

1. Squat Assessment
2. Single Leg Balance
3. Jump Landing

Use:

* pose confidence thresholds
* smoothing filters
* stability calculations
* symmetry calculations

Do NOT generate fake/random scores.

Scores must come from:

* measured angles
* movement stability
* symmetry differences
* confidence thresholds
* biomechanical rules

---

# Pose Detection

Existing pose pipeline already exists.

Preferred stack:

* MediaPipe
* MoveNet
* TensorFlow Lite

Do NOT replace pose system unless required.

---

# Existing Services

Existing services already implemented:

* ClubService
* BiomechanicsService
* PhysicalAssessmentService
* pose detection pipeline

Reuse existing logic whenever possible.

---

# Session Management Rules

Sessions should remain simple.

Session fields:

* name
* date
* team
* selected players
* enabled tests
* notes

Avoid over-complicated scheduling systems.

---

# Reports

MVP reports only need:

* player scores
* assessment history
* coach notes
* simple charts
* PDF export later

Do NOT build enterprise analytics yet.

---

# Code Style

Preferred:

* readable
* concise
* practical
* MVP-friendly

Avoid:

* unnecessary inheritance
* unnecessary abstractions
* deeply nested widgets
* huge generic builders

---

# Important

This project is currently:

* MVP first
* football club demo first
* speed and stability first

The goal is to impress a football physical coach with:

* smooth workflow
* believable scores
* clean UI
* professional assessment flow

NOT to build a full enterprise platform yet.
