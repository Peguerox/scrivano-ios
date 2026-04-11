---
name: architecture
description: Networking architecture, auth patterns, and key file map for the new SwiftUI Scrivano iOS app
type: project
---

## Stack
- Swift / SwiftUI (iOS 16+), async/await throughout — no Alamofire, no Combine for networking
- Single `APIClient` singleton (`Core/API/APIClient.swift`) — all HTTP calls go through it
- `baseURL = "https://app.scrivano.net"`
- JWT Bearer token injected automatically in `request()` via `authToken` computed property reading from Keychain
- `uploadAudio()` and `uploadDocument()` are custom methods outside the generic `request()` — each manually injects the Bearer token

## Auth
- `AuthManager` (`Core/Auth/AuthManager.swift`) — @MainActor ObservableObject, owns login/register/forgotPassword/logout
- `SocialAuthManager` (`Core/Auth/SocialAuthManager.swift`) — Google (GIDSignIn) and Apple (ASAuthorization) sign-in
- Tokens stored in Keychain via `KeychainService` (token + refresh_token + encoded User struct)
- Token refresh: `APIClient.refreshToken()` calls POST /api/auth/refresh — but it is NOT wired up to auto-retry on 401; callers receive `.unauthorized` error and must handle it themselves

## Data Models (`Core/Models/Models.swift`)
- `User`, `LoginResponse`, `Item`, `TranscriptSummary`, `NoteSummary`
- `AudioTaskResult` / `AudioTaskData` / `AudioResponseData` — audio polling models
- `NoteTaskResult`, `NoteGenerateResponse`
- `ImageProcessResponse`, `ImageTaskResult`
- `Prompt`, `PromptsResponse`
- `CollectionUploadPayload` and nested structs
- `APIError` struct for server-side error decoding

## Task Managers
- `TranscriptionManager` — upload → poll → save flow for audio
- `NoteGenerationManager` — generate → poll → save flow for notes
- `ImageProcessingManager` — process → poll flow for images
- All three live in `Core/API/TranscriptionManager.swift`
- Polling interval: 5 seconds; max attempts: 120 for audio (10 min), 60 for notes/images (5 min)

## Key Files
- `Core/API/APIClient.swift` — all HTTP primitives
- `Core/Auth/AuthManager.swift` — email/password auth
- `Core/Auth/SocialAuthManager.swift` — Google/Apple auth
- `Core/API/TranscriptionManager.swift` — audio, note, image task managers
- `Core/Models/Models.swift` — all Codable DTOs
- `Features/Auth/VerifyCodeView.swift` — OTP verify + resend
- `Features/Dashboard/DashboardView.swift` — dashboard load + collection submit + image-to-list
- `Features/Prompts/PromptsView.swift` — prompts fetch + note generation + image processing inline polling
- `Features/Text/TextListView.swift` — doc import + merge
- `Features/Notes/NotesListView.swift` — note generation via prompts
- `Features/Media/MediaListView.swift` — image picker → PromptsView
- `Features/Settings/CreditsView.swift` — credit display only (reads from AuthManager.currentUser)
- `Features/Recording/RecordingView.swift` — audio recording → TranscriptionManager
