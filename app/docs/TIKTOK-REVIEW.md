# Sandbox verification and review demonstration

## Current gate

The TikTok Production draft for app ID `7699070279028426770` has a required demo-video error. The portal states that a previously unapproved app must demonstrate the integration in a sandbox. Do not manufacture a login recording, represent sample data as actual account data, or submit the current sample-only screenshots as proof of API integration.

The native application must first compile and pass its tests on macOS. Then the account owner must authorize their TikTok sandbox account. The original Production draft has unsaved settings; preserve that page while preparing a separate sandbox configuration.

## Required end-to-end verification

1. Launch the actual macOS app and confirm the sample-data ribbon is absent.
2. Configure the sandbox app with the registered Desktop callback. Keep credentials and developer-portal secret displays out of the recording.
3. Select Connect TikTok. Show the external TikTok login/consent page and the requested read-only permissions. The account owner completes any credentials, verification challenge, and consent.
4. Show the successful return to the native app, the actual account's displayed identity, and its account statistics. This demonstrates `user.info.basic`, `user.info.profile`, and `user.info.stats`.
5. Show Videos, actual returned posts, counts, sorting, and Load older videos when more pages are available. This demonstrates `video.list`.
6. Show a comparison and export, keeping personal file paths and unrelated desktop content out of the recording.
7. Demonstrate disconnection and deletion controls. Reconnect for the owner's subsequent use if desired.

Use a real screen recording of the real app and TikTok flow. TikTok accepts MP4/MOV, up to 50 MB per video, maximum five videos according to the portal displayed during this work. Review those limits again when uploading. Review the recording for secret exposure before uploading.

## Final submission

The owner reviews the app and the recording first. Upload the approved real demonstration, verify that every selected scope is demonstrated, resolve the remaining form errors, and save the draft. Submit to TikTok only after the owner's approval.

The existing public Terms and Privacy URLs are already configured in the Production draft. A sandbox callback must be registered under Login Kit's Desktop section; the legal-site URL is not the native OAuth callback.
