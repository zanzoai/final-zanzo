Zanzo AI — Frontend (Flutter)

The official Flutter codebase powering the Zanzo AI mobile app — a real-world two-sided marketplace for tasks and earning.

The app has two modes:

🧑‍💼 User Side
	•	Create tasks
	•	AI polishes job details
	•	Pay
	•	Track live crew
	•	Chat
	•	Complete job + rate

👷‍♂️ ZenCrew (Earner) Side
	•	Receive offers
	•	Accept / reject
	•	Travel
	•	Work
	•	Verify KYC
	•	Complete & get paid

Built using:
	•	Flutter
	•	Supabase (Auth + Realtime + Storage)
	•	Stripe / Razorpay
	•	Zanzo Backend (FastAPI + Postgres + AI Engine)

⸻

1. Project Architecture

Flutter UI
↓
Services Layer (API + WebSocket + Supabase)
↓
Backend (FastAPI + Postgres + Supabase Storage)
↓
AI Models, KYC Pipelines, Job Engine, Geo Engine

⸻

2. Folder Structure Overview

lib/
│
├── core/              → Shared services, widgets, helpers
│   ├── services/
│   ├── widgets/
│   ├── helpers/
│
├── features/
│   ├── common/        → Shared screens for User + Crew
│   ├── user/          → User-only screens & widgets
│   ├── zancrew/       → Earner module (dashboard, onboarding, jobs)
│
└── main.dart          → App entry point

3. Core Layer Documentation

This layer handles everything non-UI.

core/services

Purpose:
All backend communication, uploads, OTP, KYC, chats, voice, payments, maps.

Files:

api_service.dart

Central HTTP engine.
Handles GET, POST, uploads, job events, OTP, file uploads, health check.

auth.dart

Manages login session (check login, enforce login, logout).

verification_api.dart

Full KYC engine:
PAN → Bank → Aadhaar OCR → Selfie → Liveness → Unified verification.

zancrew_api.dart

Crew side profile, onboarding state, preferences, online/offline.

messages_api.dart

Chat messages, send text, upload images.

location_helper.dart

GPS fetch + reverse geocoding.

profile_photo_helper.dart

Camera / gallery → crop → upload profile image.

razorpay_service.dart

Razorpay payment integration.

voice_ws_service.dart

Real-time mic streaming → WebSocket → Speech-to-text.

store_finder_service.dart

Unused (store lookup). Safe to remove later.

⸻

core/widgets

Reusable UI components.

location_selector.dart

Address autocomplete + store lat/lng.

payment_chip.dart

Displays Paid / COD / Cash Collected.

profile_photo_button.dart

Circular avatar picker + uploader.

verify_phone_otp_dialog.dart

Reusable OTP dialog for phone verification.

⸻

4. Features Layer

A. features/common

Shared screens for both User and Crew.

chat_screen.dart

Chat for each job.
Send messages, send photos, auto-refresh, image preview.

home_screen.dart

Main landing screen:
Voice recording → AI → Polished job → Review → Pay.

Also loads:
	•	user session
	•	avatar
	•	earn mode toggle

Future folders (job/, profile/)

Reserved for shared resources later.

⸻

B. features/user

Screens seen only by customers.

job_history_screen.dart

Shows previous jobs, statuses, and opens tracking.

profile_screen.dart

User profile: name, photo, email, logout.

review_task_screen.dart

Review polished AI task before posting.
User can edit final description.

track_job_screen.dart

Shows realtime job tracking:
	•	searching
	•	assigned
	•	travelling
	•	arrived
	•	in_progress
	•	completed

Uses:
	•	Supabase realtime
	•	PIN flows
	•	Chat access

⸻

C. features/user/widgets

Reusable user-only widgets.

add_email_dialog.dart

Add/update email.

animated_job_card.dart

Expandable job suggestion card.

change_phone_dialog.dart

Start phone update → Send OTP.

login_prompt_dialog.dart

Full login modal (name + phone + OTP + session create).

progressive_pay_button.dart

Animated pay button (idle → securing → success).

skeletons.dart

Shimmer placeholders.

⸻

5. ZenCrew (Earner) Module

Full earner module with onboarding → verification → dashboard → job flow.

Path:   

features/zancrew/
│
├── gateway/
├── onboarding/
├── dashboard/
└── screens/

A. gateway – ZanCrew Gateway

On open, automatically decides:
	•	If logged in
	•	If phone verified
	•	If preferences exist
	•	If KYC completed
	•	If ready for dashboard

Routes to:
	•	Onboarding
	•	Verification
	•	Dashboard

⸻

B. onboarding – Full Earner Onboarding Flow

Files:

welcome_screen.dart

Intro to earning with Zanzo.

phone_check_screen.dart

Checks if user has verified phone.

confirm_phone_screen.dart

Use existing phone or change number.

preferences_screen.dart

Choose:
	•	buckets (skills)
	•	radius (travel distance)

Stores locally + backend.

kyc_intro_screen.dart

KYC progress summary.

zancrew_onboarding_flow.dart

Smart router:
welcome → phone → prefs → kyc → done.

zancrew_onboarding.dart

Reusable preferences manager.

C. dashboard – ZanCrew Dashboard

Main earner panel.

Shows:
	•	online/offline
	•	GPS updates every 15 sec
	•	Inbox (offered jobs)
	•	My Jobs (accepted jobs)
	•	Edit Preferences
	•	Job cards with distance, time, pay chip

Navigation:
	•	CrewOfferDetail
	•	CrewJobDetail

⸻

D. screens – Earner Screens (Workflows)

zancrew_offer_detail.dart

Offer details:
	•	BIG price
	•	bucket
	•	title
	•	when
	•	distance live refresh
	•	Google Maps open
	•	Accept/Reject

zancrew_JobDetails.dart

Active job working screen:
	•	job title
	•	description
	•	timeline state (assigned → arrived → in_progress → completed)
	•	start/end session with PIN
	•	chat access
	•	notes & tags

zancrew_review.dart

Final summary after job completion.

zancrew_verification.dart

All-in-one KYC:
	•	PAN
	•	Bank
	•	Aadhaar OCR
	•	Face match
	•	Liveness
	•	Tier upgrades

Uses /unified/run.

⸻

6. main.dart (App Entry)

Initializes:
	•	Stripe
	•	Supabase (URL + anon key)

Sets:
	•	theme
	•	routes
	•	HomeScreen as root

⸻

7. How Data Flows (User)

User → home_screen → voice or typed input
↓
api_service.processTask()
↓
AI polishes task
↓
User reviews
↓
Posts job
↓
Dashboard finds crew
↓
Crew accepts
↓
Tracking screen shows updates (Supabase realtime)
↓
Job completes
↓
Review & payment

⸻

8. How Data Flows (ZanCrew)

Dashboard
↓
Inbox → Offer Detail
↓
Accept → JobDetails
↓
Start Session (PIN)
↓
Do job
↓
End Session (PIN)
↓
Review screen
↓
Verification (if required)

⸻

9. Developer Notes
	•	All backend calls must go through api_service.dart.
	•	All verification goes through verification_api.dart.
	•	All crew state flows through zancrew_api.dart.
	•	Do not mix UI with service logic.
	•	Keep widgets reusable.
	•	Supabase is used for:
	•	realtime job updates
	•	message storage URLs
	•	profile photos
	•	WebSockets used for voice STT.

⸻

10. Running the Project

flutter pub get
flutter run

For iOS:

cd ios
pod install

For Android:
	•	Ensure minSdkVersion is correct.
	•	Ensure Stripe keys are set.

    11. Final Summary

This README provides:
	•	A full project overview
	•	Architecture
	•	Folder structure
	•	What every file does
	•	All flows
	•	Both user and earner modules
	•	Developer notes


Just for my Note: 

a: 


             ┌──────────────────────┐
             │     Flutter UI        │
             │  (User & ZanCrew)     │
             └──────────┬────────────┘
                        │
                        ▼
         ┌──────────────────────────────────┐
         │           Services Layer          │
         │ (API / WebSocket / Supabase SDK)  │
         └───────────┬─────────┬────────────┘
                     │         │
                     │         │
         ┌───────────▼──┐   ┌──▼────────────────────┐
         │  API Service  │   │  WebSocket Services   │
         │  (REST/JSON)  │   │ (Voice STT, Realtime) │
         └──────┬────────┘   └───────────┬──────────┘
                │                        │
                ▼                        ▼
     ┌───────────────────┐      ┌───────────────────┐
     │   FastAPI Backend  │      │ Supabase Realtime │
     │  (Business Logic)  │      │  (Events + Jobs)  │
     └──────────┬────────┘      └──────────┬────────┘
                │                        │
                ▼                        ▼
     ┌───────────────────┐      ┌───────────────────┐
     │  PostgreSQL DB     │      │ Supabase Storage  │
     │ (Users, Jobs, KYC) │      │ (Images, Chat)    │
     └────────────────────┘      └───────────────────┘



    B : User Flow + Crew Flow Diagram (Very Visual)

    USER SIDE FLOW
───────────────
Create Task
  ↓
AI Polishes Task
  ↓
Review + Pay
  ↓
Waiting for Crew
  ↓
Track Job Live
  ↓
Chat + PIN + Complete


ZANCrew SIDE FLOW
──────────────────
Receive Offer
  ↓
View Details
  ↓
Accept / Reject
  ↓
Travel → Arrive → Start PIN → Work
  ↓
End PIN → Summary
  ↓
Payment + Dashboard