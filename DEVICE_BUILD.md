# Device build: unsigned IPA + free-certificate "精简版"

This document covers the second delivery path. The first one
(`.github/workflows/ios-simulator-review.yml`) builds only for the simulator; it
proves layout and animation but cannot produce a file you can install.

Goal: an **unsigned arm64 IPA** that a free personal Apple ID can re-sign, so the
app runs on a real iPhone without the 688 CNY/year Apple Developer Program.

## 1. What is produced

| Item | Value |
| --- | --- |
| Workflow | `.github/workflows/ios-device.yml` |
| Trigger | `workflow_dispatch` (manual), or push a commit touching it |
| Runner | `macos-26`, Apple Silicon, Xcode 26.x |
| Build | `-configuration Release -destination 'generic/platform=iOS'` |
| Signing | `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""` |
| Dependencies | `deps/` scripts run in their default `iphoneos` mode (no `--simulator`) |
| Output | `out/Minis-unsigned.ipa` (`Payload/Minis.app`, arm64, iOS 16.0+) |
| Artifact | `minis-unsigned-ipa`, retention 3 days |
| Build facts | branch `device-build`, file `.device-build/meta.txt` |

The facts file is there because artifact download needs a signed-in GitHub
session; `meta.txt` gives the run id, byte size, SHA-256 and log inventory
without one.

Expected wall clock: 20-28 minutes cold (queue + toolchain + native deps + app).
`deps/libs`, `deps/include` and `deps/frameworks` are cached under a `dev-media-*`
key, deliberately separate from the simulator's `sim-media-*` key: the two builds
produce different artefacts at the same paths, so a shared cache would silently
poison one of them.

## 2. App Group is now optional

The App Store build has `com.apple.security.application-groups` and gets a real
shared container. A free-certificate re-sign drops every entitlement, and
`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` then returns
`nil`. Four places force-unwrapped it, so the app died on launch
(`Fatal error: Unexpectedly found nil while unwrapping an Optional value`).

The fallback is one helper plus four call sites:

| File | Change |
| --- | --- |
| `src/ios/Shared/SharedContainerStore.swift` | new `static var containerURL: URL` — real container when entitled, otherwise `<Application Support>/MinisLocalGroup` (created on demand) |
| `src/ios/Agent/Chat/AIChatViewModel+RequestBudget.swift` | `minisAppGroupRoot`, `minisConfigRoot` use the helper instead of `containerURL(...)!` |
| `src/ios/MinisApp.swift` | the launch-time container probe uses the helper |
| `src/ios/FileProvider/FileProviderExtension.swift` | `providerRoot` falls back instead of trapping |

Audited and left alone because they were already nil-safe: `MinisApp.swift`
(FileProvider domain registration, two `guard let`), `Debug/DebugJSONRPC.swift`,
`FileProvider/FileProviderExtension.swift` (two earlier lookups),
`Views/Settings/SharedFolderVisibility.swift` (`UserDefaults(suiteName:) ??
.standard`), `Agent/Sync/CloudSyncEngine.swift` (lazy `CKContainer`). There is no
`try!` anywhere on a storage path — all 17 `try!` are `NSRegularExpression`.

A CI guard enforces this: step *Static guard, no force-unwrapped app group
container* greps for `containerURL(...) !` and fails the build if one returns.

### What still works without the entitlement

- Chat, providers, models, markdown, tool capsules, iSH terminal, jobs, memory,
  skills, shared files, the chat database — all under the app's own sandbox.
- Soul avatar (PNG and GIF) and per-session avatars.
- Import/export of backups, since they go through the document picker.

### What degrades

| Feature | Behaviour |
| --- | --- |
| iOS Files integration (`On My iPhone → Minis`) | Points at an empty per-process folder; the File Provider extension cannot see the app's files |
| Share extension (send a file into Minis) | Writes into its own sandbox; the app never receives it |
| Widget / Live Activity | Reads the fallback path; counts may stay empty |
| iCloud sync (CloudKit) | Not authenticated; sync is a no-op. Local data is unaffected |
| Push notifications | No `aps-environment`; registration fails silently |
| Health / HomeKit / WeatherKit / NFC | TCC prompts fail; nothing that runs at launch depends on them |

Nothing here is a code regression: on a properly signed build the helper returns
the real container verbatim, so behaviour is byte-identical to before.

## 3. Re-signing on the phone side

1. Download `minis-unsigned-ipa` from the run's Artifacts section.
2. In Sideloadly (or AltStore / SideStore): drop the `.ipa`, sign in with the free
   Apple ID, let it re-sign, install.
3. Trust the developer certificate in `Settings → General → VPN & Device
   Management`.
4. The certificate expires in 7 days; re-sign to renew. App data survives a
   re-sign in place, but not a delete-and-reinstall.

Observed on the simulator build: with signing disabled the app crashed on the
App Group force-unwrap. That is exactly the case the fallback above removes, and
it is the one behaviour this file cannot prove from CI — the unsigned IPA has no
runtime to log into until it is installed.

## 4. Known limits of this path

- `ANTHROPIC_OAUTH_IDENTIFIER_PROMPT` is empty in the public tree
  (`Configs/ProviderCustomization.xcconfig.example`). Anthropic API keys work;
  Claude Code OAuth does not — it hits a `fatalError` on first use by design.
- Only arm64 device slices are built; the simulator is a separate workflow.
- Release configuration, so `#if DEBUG` code (the in-app debug server, 23 of 24
  files in `src/ios/Debug/`) is not present.
- The IPA is unsigned and unverified by Apple: first launch may show an
  untrusted-developer warning until step 3 above.

## 5. Reading results without a token

```
run status   https://github.com/ou619/ooom/actions?t=1        (HTML carries embedded JSON)
build facts  https://raw.githubusercontent.com/ou619/ooom/device-build/.device-build/meta.txt
failure logs https://raw.githubusercontent.com/ou619/ooom/device-logs/.device-logs/meta.txt
```

`raw.githubusercontent.com` caches for minutes and rejects a `?t=` query string
(404). To see a fresh `meta.txt`, go through the contents API with
`Accept: application/vnd.github.raw` and `?ref=device-build`.