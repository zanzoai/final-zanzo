# ZanCrew Onboarding (Complete Folder Guide)

This folder handles the **entire onboarding journey** for earners joining
ZanCrew — from phone verification → preferences setup → KYC → dashboard.

It ensures that every new ZanCrew member completes all required steps
smoothly and in the correct order.

---

# 📂 FILE STRUCTURE OVERVIEW
onboarding/
│
├── confirm_phone_screen.dart
├── kyc_intro_screen.dart
├── phone_check_screen.dart
├── preferences_screen.dart
├── welcome_screen.dart
├── zancrew_onboarding_flow.dart
└── zancrew_onboarding.dart

Below is the **purpose, flow, and usage** of each file.

---

# 1) **welcome_screen.dart**
### **Purpose**
- First screen the user sees when choosing “Earn with Zanzo”.
- Introduces the concept: flexible earning, instant payouts, nearby jobs.

### **What it does**
- Shows a “Start” button → begins onboarding
- Navigates to `ZanCrewPhoneCheckScreen`

### **Navigation**

Welcome → Phone Check
---

# 2) **phone_check_screen.dart**
### **Purpose**
Determine if the user already has a verified phone number.

### **Logic**
| Case | Action |
|------|--------|
| User already has `user_phone` + `phone_verified = true` | Go to `ConfirmPhoneScreen` |
| User NOT verified | Show OTP popup (`showLoginPrompt`) |

### **Navigation**
PhoneCheck → ConfirmPhone (if verified)
PhoneCheck → OTP login → Preferences (if new)

---

# 3) **confirm_phone_screen.dart**
### **Purpose**
When a user already has a verified phone → ask:

**“Do you want to use this number for ZanCrew?”**

### **Actions**
- “Use this number” → go to `ZanCrewPreferencesScreen`
- “Change number” → restart OTP flow

### **Navigation**

ConfirmPhone → Preferences
ConfirmPhone → PhoneCheck (for change)

---

# 4) **preferences_screen.dart**
### **Purpose**
Collect first-time user preferences:
- Skill categories (buckets)
- Service radius (how far they travel)

### **What it stores**
Locally in SharedPreferences:
- `zancrew_buckets`
- `zancrew_radius_km`

Backend:
- Creates/upserts ZanCrew profile with status = `"pending"`

### **Navigation**

Preferences → KYC Intro

---

# 5) **kyc_intro_screen.dart**
### **Purpose**
Show the entire KYC progress and explain what is required.

### **Checks**
Fetch from backend:
- PAN verified?
- Bank verified?
- Aadhaar OCR verified?
- Selfie + liveness verified?

### **What it displays**
- Progress bar (0/4 → 4/4)
- Cards explaining each verification step
- CTA “Begin Verification”

### **Navigation**

KYC Intro → ZanCrewVerification (full flow)
KYC Intro → Dashboard (after all verified)

---

# 6) **zancrew_onboarding.dart**
### **Purpose**
Reusable Preferences Screen (old name).
- Used for first-time OR edit mode
- Includes edit-limit logic (max 2 edits/week)

### **When used**
- In some flows instead of `preferences_screen.dart`
- Also used by active earners updating preferences

---

# 7) **zancrew_onboarding_flow.dart**
### **Purpose**
⚡ **Smart router for onboarding**

It decides "where the user should go next" based on backend state:

Checked fields:
- Does ZanCrew profile exist?
- What onboarding step are they on?
  - `welcome`
  - `phone`
  - `prefs`
  - `kyc`
  - `done`

### **Navigation Examples**

No profile → Welcome
Step = phone → phone_check_screen
Step = prefs → preferences_screen
Step = kyc → KYC Intro
Step = done → Dashboard

This file makes onboarding **resume-able** and prevents broken flows.

---

# 🔄 FULL ONBOARDING FLOW (VISUAL)

Welcome
↓
PhoneCheck
↓ (verified)
ConfirmPhone
↓
Preferences
↓
KYC Intro
↓
Verification Steps (PAN → Bank → Aadhaar → Selfie)
↓
ZanCrew Dashboard

---

# 🗝 Shared Preferences Keys Used Across This Folder

| Key | Meaning |
|------|---------|
| `user_phone` | Logged-in user's phone |
| `phone_verified` | Was OTP verified? |
| `user_id` | Unique user ID |
| `zancrew_buckets` | Selected skills |
| `zancrew_radius_km` | Travel distance |
| `zancrew_status` | active / pending |
| `zancrew_enabled` | Whether earner mode is ON |
| Edit-limit keys | Used by `zancrew_onboarding.dart` |

---

# ✔️ Summary

This folder provides the **entire end-to-end onboarding logic** for ZanCrew:

- Starts with a friendly welcome
- Ensures verified phone
- Collects preferences
- Handles full KYC pipeline
- Resumes onboarding if interrupted
- Final step → takes user to Dashboard
