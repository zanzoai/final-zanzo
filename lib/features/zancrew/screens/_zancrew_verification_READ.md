1. zancrew_verification.dart

Purpose:
Full KYC verification flow for ZenCrew workers.

What it does:
	•	Collects PAN, Bank, Aadhaar (front/back), and Selfie
	•	Performs OCR on Aadhaar front
	•	Handles Razorpay payment
	•	Sends a unified verification payload to backend
	•	Shows progress (0/4 → 4/4)
	•	Displays structured error messages
	•	Redirects to ZenCrew Dashboard after success

When shown:
After the user completes skill preferences (radius + buckets).

⸻

2. zancrew_offer_detail.dart

Purpose:
Shows details of a job offer sent to a ZenCrew member.

What it does:
	•	Displays the polished_job title
	•	Shows distance, pay, address, instructions
	•	Allows user to Accept or Reject
	•	Calls /zancrew/offers/{id}/accept or reject
	•	Redirects to active job tracking

When shown:
From the “Offers” list or live push notification.

⸻

3. zancrew_review.dart

Purpose:
Allows the ZenCrew worker to review job summary after completion.

What it does:
	•	Shows job details, time taken, earnings
	•	Collects rating/comments (TODO optional now)
	•	Confirms job completion and moves status to settled
	•	Used for worker performance metrics

When shown:
After crew completes the job (post “Complete Work”).

⸻

4. zancrew_jobDetails.dart

Purpose:
Real-time job progress UI for active jobs.

What it does:
	•	Shows current job status timeline
	•	Buttons: Start → Arrived → Start Work → Complete
	•	Polls or listens to job updates
	•	Displays customer address, phone masking, chat link (future)
	•	Ensures job flow follows valid sequence

When shown:
Immediately after offer acceptance.

⸻

🧩 How These Screens Connect
Offers List → Offer Detail → Accept → JobDetails → Review
                            ↓ (Reject)
                         Offer removed
Preferences → Verification → Dashboard → (Offers, Active Jobs)