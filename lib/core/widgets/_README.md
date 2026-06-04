📁core/widgets — UI Components

Reusable UI widgets used across multiple screens in the app.
Each widget is self-contained and handles only presentation + small logic.

⸻

📌 Files Overview

1. location_selector.dart
	•	Google Places autocomplete search bar.
	•	Lets user pick an address and validates if the location falls inside service areas.
	•	Saves selected address + lat/lng into SharedPreferences.

⸻

2. payment_chip.dart
	•	Small coloured UI chip showing payment mode & status.
	•	Online → Paid (green)
	•	COD → Cash in Hand or Cash Collected (auto-green when job completes).

⸻

3. profile_photo_button.dart
	•	Circular avatar component used in Profile screen.
	•	Lets user capture/upload photo → uploads via ApiService.uploadProfilePhoto.
	•	Shows upload loading state.

⸻

4. verify_phone_otp_dialog.dart
	•	Reusable OTP dialog used during phone number update flow.
	•	Accepts 6-digit code → verifies via ApiService.verifyUpdatePhoneOtp.
	•	Returns true/false based on success.

⸻

🧱 Purpose of this Folder
	•	Keep UI components modular
	•	Avoid repeating the same widget code in multiple screens
	•	Keep features/ screens cleaner and focused only on flow logic

⸻

📌 When to Add New Widgets Here

Add here when:
	•	The widget is used in multiple places
	•	The widget manages small UI logic
	•	The widget should not depend on specific screens

Examples:
buttons, chips, selectors, dialogs, cards, small reusable UI elements.