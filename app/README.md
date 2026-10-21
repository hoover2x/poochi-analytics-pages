# Poochi Analytics

Private, native macOS workspace for the Poochi & Friends TikTok account. SwiftUI and Swift Charts; macOS 13 or later. No third-party application dependencies or hosted backend.

## What is implemented

- A native overview with account followers, following, likes, public-video count, and an observation-based follower chart.
- TikTok Desktop Login Kit: external-browser OAuth, cryptographically random state and verifier, TikTok's hexadecimal SHA-256 PKCE challenge, and a loopback-only callback listener.
- Keychain storage for the app secret and tokens, access-token refresh, refresh-token rotation, and TikTok access revocation.
- Read-only profile and paginated public-video API requests, restricted to fields covered by the permissions actually granted.
- Search, posting-date filters, sorting, comparison of up to three videos, and CSV export of views, likes, comments, shares, and calculated engagement.
- Local analytics storage, offline access to saved observations, deletion controls, and a clearly labeled sample workspace.
- An Xcode app project, a Swift package for core regression tests, a native UI smoke test, and a GitHub Actions workflow that builds a universal Mac app and retains test evidence.

Video figures are lifetime counts for loaded videos. The date selector filters when a video was posted; it does not turn lifetime views into views earned in a reporting period. Missing values remain unavailable. Engagement is `(likes + comments + shares) / views`; it is undefined for zero views or incomplete inputs. Account history begins with actual daily observations, retaining up to 366 observations. A refresh replaces the video list with the newest page; use **Load older videos** to include additional posts in totals and comparisons.

## Verification status

Source and project files have been created. Swift source syntax, Xcode object references, the shared scheme, resource plists, workflow structure, and shell script syntax have been checked. The source package is **not yet a verified Mac build**. This development workspace is Linux and does not include Swift or Xcode. The included XCTest suites and macOS workflow must run on a Mac before the app is marked ready for testing.

The existing project repository is [hoover2x/poochi-analytics-pages](https://github.com/hoover2x/poochi-analytics-pages). The native application lives under `app/`, alongside the existing public legal pages. Application development is reviewed on a separate branch. No production submission has been made to TikTok.

## Open and build

Open `PoochiAnalytics.xcodeproj` in Xcode 15 or later, select the **PoochiAnalytics** scheme, and Run. Alternatively, run:

```bash
bash scripts/build.sh
```

This runs the core tests and builds an ad hoc signed, universal `arm64`/`x86_64` application at `build/Build/Products/Release/Poochi Analytics.app`. It also creates a ZIP under `build/deliverables`. `Build-and-Open.command` wraps that sequence and opens the app. No Apple Developer signing identity is required for this private development build; it is not notarized or intended for public distribution.

To run native UI verification:

```bash
xcodebuild -project PoochiAnalytics.xcodeproj -scheme PoochiAnalytics \
  -destination 'platform=macOS' -derivedDataPath build-ui \
  -resultBundlePath build/Poochi-UI.xcresult \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual test
```

The native UI test launches with `--sample`; it does not authenticate or use real account data. `swift test` exercises the isolated core module. The app project compiles that same core source directly, without a generated package dependency. Regenerate project references after adding files with `python3 scripts/generate_project.py`.

## Connect the TikTok sandbox

1. In the TikTok Developer Portal, select the Poochi Analytics **Sandbox** configuration and add the intended TikTok account as a sandbox target user.
2. Enable Login Kit for Desktop and the read-only scopes `user.info.basic`, `user.info.profile`, `user.info.stats`, and `video.list`. Configure Display API access if required by the portal for video access.
3. Register the exact Desktop redirect `http://127.0.0.1:8787/callback/`. If that port is occupied, register another explicit loopback port and update the app's setting to match.
4. Enter the sandbox client key and secret in the app's Settings, save, and select **Connect TikTok**. The account owner completes TikTok's consent in their browser.
5. Verify the account identity and granted permissions, then refresh, load older videos, compare posts, and test export. Actual access depends on TikTok's scope and sandbox configuration.

Credentials belong only in the app's secure Settings. They are never stored in this repository, build artifacts, Actions secrets, or test fixtures. Sandbox and production use the same documented API endpoints; the client credentials select the environment. Disconnect before replacing the credentials. This is a private single-owner app: the user supplies the app secret locally. Public distribution would require a separate credential architecture review.

## TikTok review recording

The existing Production draft requires a demonstration video before it can be saved/submitted. That draft is not a substitute for a sandbox test. Follow [docs/TIKTOK-REVIEW.md](docs/TIKTOK-REVIEW.md) after the Mac build and sandbox flow work. A sample-data demonstration cannot prove real OAuth integration. The account owner must approve the real TikTok consent and the final production submission.

## Data and limits

The app requests no publishing, comment-writing, follower-identity, or messaging access. It does not scrape TikTok, automatically post content, or send analytics to an AI provider. Watch time, retention, demographics, and revenue are not implemented because the selected endpoints do not supply those fields.

The secret and token pair are in this app's macOS Keychain service. Analytics live in an owner-only `PoochiAnalytics/analytics.json` file under the app's Application Support location (inside its container when using the sandboxed Xcode build). Disconnect attempts remote revocation before clearing local data. **Remove local account data** is also available offline; it does not revoke TikTok's remote grant. Exported CSV files are outside the app's deletion control. Client settings remain when account data is deleted.

## Official API references

Implementation checked against TikTok's documentation on October 21, 2026:

- [Login Kit for Desktop](https://developers.tiktok.com/doc/login-kit-desktop/)
- [Token exchange, refresh, and revocation](https://developers.tiktok.com/doc/oauth-user-access-token-management/)
- [User info and scope-to-field mapping](https://developers.tiktok.com/doc/tiktok-api-v2-get-user-info)
- [Paginated video list](https://developers.tiktok.com/doc/tiktok-api-v2-video-list/)
- [Video metric fields](https://developers.tiktok.com/doc/tiktok-api-v2-video-object)

Existing legal pages remain at [Poochi Analytics](https://hoover2x.github.io/poochi-analytics-pages/). No other application project was changed.
