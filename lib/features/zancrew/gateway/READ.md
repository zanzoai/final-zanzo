📄 ZanCrew Gateway — README

The ZanCrew Gateway is the decision router that determines where a user should be directed inside the ZanCrew (earner) module.

It automatically checks the user’s login state, onboarding progress, and verification status, then redirects accordingly.

⸻

🚦 What This Gateway Does

When opened, the gateway performs these steps:

1. Check if user is signed in
	•	Requires user_phone
	•	If missing → shows error → pops back to previous screen

2. Validate user account
	•	Requires user_id
	•	If missing → error → pop

3. Fetch profile via API
	•	Calls ZanCrewApi.getProfile(userId)
	•	If profile is null → send user to onboarding

4. Route the user based on profile state

A. Missing Preferences
	•	buckets.isEmpty == true
→ Send to ZanCrewOnboarding

B. Missing Any Verifications

User must complete ALL of these:
	•	Bank verification
	•	KYC verification
	•	Aadhaar verification
	•	Liveness
	•	Face match
	•	Status == “active”

If ANY are missing → send to:
→ ZanCrewVerification(userId)

C. Fully Verified

If all checks pass → continue to:
→ ZanCrewDashboard
