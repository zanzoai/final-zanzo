📘 Zanzo Frontend — Services Layer (README)

This folder contains all the backend communication, websocket, media, and utility logic for the Zanzo app.
These services are independent of UI and can be used anywhere across the project.

⸻

## 🧱 What This Folder Does
	•	Connects Flutter → Backend API
	•	Handles OTP, auth, KYC, maps, chat, payment, and audio
	•	Uploads images, profile photos, chat media
	•	Manages WebSocket connections (voice + real-time flows)
	•	Provides reusable helper utilities

⸻

## 📂 Files & Their Responsibilities

### 1️⃣ api_service.dart

One-line summary:
Central API engine: builds URLs, handles GET/POST, errors, job events, OTP, uploads, and all HTTP requests.

Handles:
	•	Network calls
	•	JSON headers
	•	Health check
	•	Job creation/session updates
	•	Crew offers & jobs
	•	Phone OTP flows
	•	Profile photo upload
	•	WebSocket URL generation

⸻

### 2️⃣ auth.dart

One-line summary:
Phone-based login manager: checks sign-in status, opens login modal, and handles sign-out.

Handles:
	•	Check if user is logged in
	•	Force login before opening profile
	•	Remove local auth data

⸻

### 3️⃣ verification_api.dart

One-line summary:
Full KYC engine: PAN, bank, Aadhaar OCR, selfie, unified verification, and state sync with server.

Handles:
	•	Start PAN verification
	•	Bank verification
	•	Fetch verification status
	•	Unified verification workflow
	•	Sync profile state after verify

⸻

### 4️⃣ zancrew_api.dart

One-line summary:
Crew engine: save/get profile, check onboarding state, set online, dev-verify, and load job ratings.

Handles:
	•	Upset crew profiles (skills, radius, status)
	•	Get crew profile
	•	Get crew onboarding state
	•	Set online/offline
	•	Dev verify
	•	Rating fetch

⸻

### 5️⃣ messages_api.dart

One-line summary:
Chat engine: load messages, send text, upload image bytes, and send image messages.

Handles:
	•	List chat messages per job
	•	Send text message
	•	Upload chat image to Supabase
	•	Send image message after upload

⸻

### 6️⃣ location_helper.dart

One-line summary:
GPS manager: get user’s live location and convert lat/lng to readable address.

Handles:
	•	Request permissions
	•	GPS fetch
	•	Reverse geocoding

⸻

### 7️⃣ profile_photo_helper.dart

One-line summary:
Photo helper: capture from camera, pick from gallery, crop image, then upload.

Handles:
	•	Camera
	•	Gallery
	•	Crop

⸻

### 8️⃣ razorpay_service.dart

One-line summary:
Payment engine: creates Razorpay orders via backend and opens the Razorpay checkout UI.

Handles:
	•	Init Razorpay listeners
	•	Create order through backend
	•	Launch Razorpay UI
	•	Send callbacks back to app

⸻

### 9️⃣ voice_ws_service.dart

One-line summary:
Streams mic audio to backend over WebSocket and receives final speech-to-text results.

Handles:
	•	Start audio recorder
	•	Stream PCM bytes
	•	WebSocket connection
	•	Get final transcripts

⸻

### 🔟 store_finder_service.dart (not used currently)

One-line summary:
(Unused) Google Places lookup for nearby stores based on task text.

Note: Kept for now — can delete later.


System Flow Diagram (Text):

User Action
   ↓
UI Screen
   ↓
Service Layer (this folder)
   ↓   (HTTP / WebSocket / Supabase)
Backend APIs / WebSocket Server / Storage
   ↓
Processed Response
   ↓
UI Updates


Developer Notes
	•	All network calls must go through api_service.dart.
	•	All WebSocket flows must use voice_ws_service.dart.
	•	All chat media storage uses Supabase bucket chat_uploads.
	•	Do NOT put UI code inside services — keep them pure logic.
	•	When writing new features, add new services here to keep consistency.