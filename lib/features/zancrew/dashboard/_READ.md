# ZanCrew Dashboard

The **ZanCrew Dashboard** is the main control panel for earners (ZenCrew partners).  
It shows their online status, preferences, and all incoming / accepted jobs.

---

## Responsibilities

- Display whether **ZanCrew Mode** is enabled for the user.
- Let the earner **Go Online / Offline**.
- Start and stop **GPS location updates** to the backend while online.
- Show two tabs:
  - **Inbox** → job offers with status `offered`
  - **My Jobs** → accepted jobs with status `accepted`
- Render each job card with:
  - Category (bucket)
  - Price estimate
  - When label
  - Distance
  - Payment info chip (`Paid Online`, `Cash in Hand`, `Cash Collected`)
- Navigate into:
  - **CrewOfferDetail** (accept / reject)
  - **CrewJobDetail** (track an accepted job)

---

## Local State & Storage

The dashboard uses `SharedPreferences` to store:

- `zancrew_enabled` – whether ZanCrew earner mode is turned on from profile.
- `zancrew_online` – whether the earner is currently online.
- `zancrew_radius_km` – search radius for jobs (1–50 km).
- `zancrew_buckets` – selected job categories (e.g., Delivery, Cleaning).
- Migration from older keys:
  - `earner_enabled`, `earner_radius_km`, `earner_buckets`, `earner_online`.

On first activation, it also shows a one-time banner:

- Key: `zancrew_activation_banner_shown`

---

## Online / Offline Behaviour

When **Go Online** is turned on:

1. Dashboard calls `ZanCrewApi.setOnline(userId, true)`.
2. Starts a 15-second timer that:
   - Reads GPS location using `geolocator`.
   - Sends it to backend via `ApiService.postCrewLocationUpdate`.
3. Fetches offers for the active tab using:
   - `ApiService.fetchCrewOffers(crewUserId, status, limit)`

When toggled **Offline**:

- Stops the timer.
- Updates local preference and backend online flag.

---

## Preferences Editing

The **Edit Preferences** button in the AppBar opens a bottom sheet where the earner can:

- Toggle **Categories (buckets)** using `FilterChip`.
- Adjust **Radius (km)** using a `Slider`.

On save:

1. Values are stored in `SharedPreferences`.
2. Dashboard calls `ZanCrewApi.getProfile` to read current `status`.
3. Calls `ZanCrewApi.upsertProfile` with:
   - `userId`
   - `buckets`
   - `radiusKm`
   - `status`:
     - If the profile was already `active`, keep it `active`.
     - Otherwise keep it `pending`.

---

## Tabs & Navigation

- Tabs are controlled via `_currentTab`:
  - `'offered'` → Inbox
  - `'accepted'` → My Jobs

- Job tap actions:
  - In **Inbox**:
    - Push `CrewOfferDetail(offer: ...)`
    - After return, refresh offers if result is `'accepted'` or `'rejected'`.
  - In **My Jobs**:
    - If `job_id` is present, push `CrewJobDetail(jobId: job_id)`.

---

## File Path

```text
lib/features/zancrew/dashboard/zancrew_dashboard.dart