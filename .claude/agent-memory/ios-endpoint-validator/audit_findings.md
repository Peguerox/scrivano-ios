---
name: audit_findings
description: Recurring issues and patterns discovered during iOS endpoint audits for Scrivano
type: project
---

## Audit: March 2026 — New SwiftUI app vs Next.js 14 backend

### Issues found (for future re-audits, recheck these)

1. **VerifyCodeView calls /api/auth/confirm-code — endpoint not in spec**
   - File: `Features/Auth/VerifyCodeView.swift` line 213
   - The verify step POSTs to `/api/auth/confirm-code` with `{email, code}`, but no such endpoint was provided in the backend spec. The spec only has `/api/auth/reset-password` and `/api/auth/resend-code`.
   - The resend call in the same file omits the required `type` field.

2. **CreditsView does NOT call /api/user/credits — reads stale local data**
   - File: `Features/Settings/CreditsView.swift`
   - No network call is made. Displays `auth.currentUser?.credit` from Keychain cache only.
   - The backend spec provides GET /api/user/credits specifically for this purpose.

3. **POST /api/notes/save — field name casing mismatch**
   - File: `Core/API/APIClient.swift` line 200–218
   - iOS sends `itemId` and `promptLabel` in camelCase JSON keys.
   - Backend spec shows `{text, itemId, promptLabel?}` — acceptable only if the backend actually handles camelCase. Needs verification against backend implementation.

4. **POST /api/audio/save-transcript — field name casing mismatch**
   - File: `Core/API/APIClient.swift` line 299–319
   - iOS sends `itemName`, `collectionName`, `durationSeconds` in camelCase.
   - Backend spec shows `{text, itemName, collectionName, durationSeconds?}` — same camelCase risk.

5. **No 401 auto-retry / token refresh wiring**
   - `APIClient.refreshToken()` exists but is never called automatically when a request returns 401.
   - Callers propagate `.unauthorized` to the UI. If the JWT expires mid-session, the user gets an error dialog rather than a silent re-auth.

6. **TranscriptionManager poll loop silently swallows all errors**
   - File: `Core/API/TranscriptionManager.swift` line 91–93
   - The `catch` block inside the poll loop does nothing, meaning transient AND permanent server errors are both silently retried until timeout.
   - Same pattern in NoteGenerationManager and ImageProcessingManager.

7. **PromptsView inline polling not cancellable**
   - File: `Features/Prompts/PromptsView.swift` — the `apply()` function runs a `while` loop directly inside a SwiftUI async context with no stored Task reference, so it cannot be cancelled if the user dismisses the sheet.

8. **DashboardView image-to-list polling not cancellable**
   - File: `Features/Dashboard/DashboardView.swift` `createListFromImage()` — same pattern.

9. **AudioTaskResult status string: spec says "running", code checks "completed"/"failed" with default fallback**
   - The code uses `default:` to handle "running" which is correct, but any new status value from the backend (e.g. "queued") would fall through silently.
