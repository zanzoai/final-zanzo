# 🧭 ZanCrew Screens — Module Documentation
This folder contains **all UI screens for ZenCrew workers**.  
Each screen handles one specific part of the job lifecycle — from receiving an offer → reviewing → verifying → completing.

---

## 📌 Folder Overview
screens/
│
├── zancrew_offer_detail.dart      → Offer details (before accepting)
├── zancrew_JobDetails.dart        → Active job details (after accepting)
├── zancrew_review.dart            → Final review summary (post-completion)
└── zancrew_verification.dart      → Verification checks (ID, KYC, face match)

---

# 1️⃣ **Offer Detail Screen**  
**File:** `zancrew_offer_detail.dart`  
**Purpose:**  
Shown when a crew member opens a job offer in their Inbox.

### 🔹 Key Features
- Shows BIG price, bucket, title, when, distance  
- Shows polished description & address (tap → open Google Maps)  
- Shows duration & number of people  
- Shows payment mode (Online / COD)  
- Sticky bar at bottom for **Accept / Reject**  
- Live refresh of distance (`GET /zancrew/offers/{offer_id}`)  
- Fetches full job once for deeper details (`GET /jobs/{job_id}`)

### 🔹 API Used
- `GET /jobs/{id}`
- `GET /zancrew/offers/{offer_id}`
- `POST /zancrew/offers/{offer_id}/accept`
- `POST /zancrew/offers/{offer_id}/reject`

---

# 2️⃣ **Active Job Detail Screen**  
**File:** `zancrew_JobDetails.dart`  
**Purpose:**  
Displayed after job is **accepted**.  
This is the **main working screen** during task execution.

### 🔹 Key Features
- Shows price, job title, address, description  
- Shows current status → and next status CTA  
  - assigned  
  - travelling  
  - arrived  
  - in_progress  
  - completed  
- Shows **friendly time summary card**  
  - minutes worked  
  - total duration  
  - progress bar  
- Chat button (enabled once job is assigned)  
- Important notes + tags  
- Fully integrated Start PIN / End PIN flows  
- Manual refresh

### 🔹 API Used
- `GET /jobs/{id}`
- `GET /jobs/{id}/session`
- `POST /jobs/{id}/events`
- `POST /jobs/{id}/session/start` (PIN required)
- `POST /jobs/{id}/session/end` (PIN required)

---

# 3️⃣ **Review Screen**  
**File:** `zancrew_review.dart`  
**Purpose:**  
After completing the job, crew sees a summary.

### 🔹 Key Features
- Shows job summary & what was done  
- Displays time spent (from session_summary)  
- Shows earnings summary  
- Next step: “Mark as Done” or simple completion message  
- May also show option for rating the customer (future)

### 🔹 API Used
- `GET /jobs/{id}`
- (Sometimes) `GET /jobs/{id}/session`

---

# 4️⃣ **Verification Screen**  
**File:** `zancrew_verification.dart`  
**Purpose:**  
Handles **crew onboarding verification**, including:

- Phone verification  
- ID verification  
- Aadhaar OCR  
- PAN OCR  
- Face Liveness  
- Face Compare  
- Tier upgrades (Tier0 → Tier1 → Tier2)  

### 🔹 Features
- Shows current verification tier  
- Shows pending steps  
- Uploads documents + selfie  
- Shows error messages clearly  
- Sequential workflow  

### 🔹 API Used
- `POST /unified/run`
- `GET /zancrew/state`
- `POST /zancrew/update_verification_step`

---

# 🔥 How All Screens Connect (Flow)

Offers List
↓ (tap)
Offer Detail Screen
↓ Accept
Active Job Details Screen
↓ complete
Review Screen

Verification is separate:
ZanCrew Gateway → Verification Screen → Dashboard

---

# 🎯 Design Principles Used

- Clean separation of logic (each screen = one purpose)
- JSON maps normalized to `Map<String, dynamic>`
- All backend calls go through `ApiService`
- UI segmented into readable sections
- Friendly UX:
  - sticky action bars
  - progress indicators
  - inline error messages
- Safe `mounted` checks everywhere

---

# ✔️ If you add a new screen…
Follow the same header format:

```dart
// -----------------------------------------------------------------------------
// Screen Name — Purpose
// Summary of what this screen does
// Endpoints used
// Key state variables
// -----------------------------------------------------------------------------