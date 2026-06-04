# 📁 features/common/

This folder contains **shared screens** that are used by both the User app and the ZanCrew (Earner) side.  
Anything that is “universal” across the whole app belongs here.

---

## 📂 chat/
**File:** `chat_screen.dart`  
**Purpose:**  
UI + logic for the in-app chat used between **User ↔ ZanCrew** for each job.

**Key features:**
- Fetch messages for a job  
- Send text messages  
- Send photo messages (with compression + extension detection)  
- Auto-refresh every 2 seconds  
- Auto-scroll to latest message  
- Left/right bubble alignment  
- Image preview dialog  

---

## 📂 home/
**File:** `home_screen.dart`  
**Purpose:**  
Main landing screen for the User app — accepts typed/voice tasks and sends them to `/process_task`.

**Key features:**
- Voice recording → STT → append final text  
- Free-type or speak job requests  
- Auto-typing example prompts (ticker)  
- Sends request to backend and opens ReviewTaskScreen  
- Shows avatar (profile) and Earn icon (ZanCrew toggle)  
- Loads user prefs + ZanCrew status  

---

## 📂 job/
**(Empty for now — reserved for future)**  
This folder will contain:
- Job detail screen  
- Job tracking screen (timeline updates)  
- Cancel job, rating UI, etc.

---

## 📂 profile/
**(Empty for now — reserved for future)**  
This folder will contain:
- Profile editing screen  
- Address management  
- Payment history  
- Verification status  

---

### 🔖 Notes
- `common/` holds things that can be used by **any feature** (user or earner).  
- If a screen belongs ONLY to the user side, put it under `features/user/`.  
- If a screen belongs ONLY to ZenCrew, put it under `features/zancrew/`.

---

✔ **Clean, organised, and future-ready.**  
Tell me when you want the next README.