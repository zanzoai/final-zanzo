📄 README.md — User Widgets (Zanzo Frontend)

This folder contains reusable UI components used across the User side of the Zanzo App.
All widgets here are stateless/stateful UI helpers — no business logic is changed.

⸻

📁 Files Overview

1. add_email_dialog.dart

A popup dialog for adding or updating the user’s email.
Includes:
	•	Email validation
	•	Saving email to SharedPreferences
	•	API call → ApiService.updateEmail()

Used inside Profile → “Add/Update Email”.

⸻

2. animated_job_card.dart

Expandable / collapsible animated job card used in job suggestions or job list screens.
Shows:
	•	Job title
	•	Requirements
	•	Preview of actions (collapsed)
	•	All actions + tags (expanded)

Smooth animations using AnimatedContainer.

⸻

3. change_phone_dialog.dart

A modal dialog for updating a user’s phone number.
Flow:
	1.	User enters new phone
	2.	Format validated with regex
	3.	Calls backend → sendUpdatePhoneOtp()
	4.	Returns phone string to caller for OTP verification screen

Only sends OTP, does NOT verify.

⸻

4. login_prompt_dialog.dart

Full OTP login flow inside an AlertDialog.
Handles:
	•	Name entry
	•	Phone entry
	•	Send OTP
	•	Verify OTP
	•	Store user_id, tokens, name, phone, ZanCrew defaults

Returns true when login succeeds.

⸻

5. progressive_pay_button.dart

Interactive animated payment button used before confirmations.
States:
	•	idle → checking → securing → success → idle (auto reset)
	•	Customizable prefix (“Pay ”), color, currency, and trailing notes

Calls onConfirmed() when payment succeeds.

⸻

6. skeletons.dart

Shimmer-based skeleton placeholders used during loading.
Components:
	•	TaskSkeleton → full card loading placeholder
	•	PriceSkeleton → small price row placeholder
	•	ButtonSkeleton → full-width button loading placeholder

Uses custom shimmer animation.

⸻

📌 Purpose of This Folder

These widgets improve user experience, add visual consistency, and reduce code duplication across screens.
All widgets are plug-and-play and rely on core services already implemented.