# Releasing Mara

Mara ships as a **Developer ID–signed, notarized DMG** (drag-to-Applications). This is the orthodox
path for a non–App Store macOS menu-bar app. Mara requires **no special permissions** (no sandbox,
no Accessibility/Location/Screen-Recording), so notarization is clean and there are no first-launch
TCC prompts.

## One-time prerequisites

1. **Apple Developer Program** membership (paid). The "Apple Development" certificate used for local
   runs is for development only and **cannot** be used to distribute.
2. A **Developer ID Application** certificate in your login keychain
   (Xcode → Settings → Accounts → Manage Certificates → +, or the Developer portal).
   You already have one: team `7K6MK3KP9K`.
3. A notarization credential — either:
   - a keychain profile:
     `xcrun notarytool store-credentials mara-notary --apple-id <id> --team-id 7K6MK3KP9K --password <app-specific-password>`, or
   - an **app-specific password** (appleid.apple.com → Sign-In & Security → App-Specific Passwords).

## Local release

```bash
DEVELOPMENT_TEAM=7K6MK3KP9K \
NOTARY_PROFILE=mara-notary \
make release            # or: ./scripts/release.sh 1.0.0
```

Or with an Apple ID instead of a stored profile:

```bash
DEVELOPMENT_TEAM=7K6MK3KP9K \
APPLE_ID=you@example.com \
APPLE_APP_PASSWORD=abcd-efgh-ijkl-mnop \
./scripts/release.sh 1.0.0
```

Output: `dist/Mara-<version>.dmg` — signed, notarized, stapled. The version defaults to the latest
git tag (leading `v` stripped) when omitted. `scripts/release.sh` runs
`scripts/generate-project.sh` first, since `Mara.xcodeproj` is generated and gitignored. The helper
restores the committed `config/Package.resolved`, and release builds disable automatic package
resolution so the audited Sparkle revision cannot drift behind the same version tag.

> Multiple Developer ID certs? Pass an explicit identity:
> `DEVELOPER_ID_IDENTITY="Developer ID Application: Your Name (7K6MK3KP9K)"`.

## Automated release (GitHub Actions)

Pushing a tag builds and publishes automatically:

```bash
git tag v1.0.0
git push origin v1.0.0
```

`.github/workflows/release.yml` then builds → signs → notarizes → packages the DMG → verifies it →
signs the DMG with the Sparkle EdDSA key and generates `appcast.xml` → creates a **GitHub Release**
with the DMG, its `.sha256`, and `appcast.xml` attached, plus auto-generated notes. Installed apps
pick the update up from `releases/latest/download/appcast.xml` (pre-releases — hyphenated tags —
are excluded from `latest` automatically).

The release job runs in a protected **`release` environment** and all actions are pinned to commit
SHAs (Dependabot keeps them current). With a required reviewer on the environment, a pushed tag
**waits for human approval** before the signing/notarization secrets are exposed — so a stolen tag
push cannot publish a signed build on its own.

### Required secrets (set on the `release` environment)

Add these under **Settings → Environments → `release` → Environment secrets** (preferred over
repo-wide secrets, so only the approved release job can read them):

| Secret | What |
|--------|------|
| `DEVELOPER_ID_CERT_P12` | Developer ID Application cert + private key exported as `.p12`, base64-encoded (`base64 -i cert.p12 \| pbcopy`) |
| `DEVELOPER_ID_CERT_PASSWORD` | password set when exporting the `.p12` |
| `APPLE_TEAM_ID` | Apple Developer Team ID (`7K6MK3KP9K`) |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_APP_PASSWORD` | app-specific password for that Apple ID |
| `SPARKLE_ED_PRIVATE_KEY` | EdDSA private key that signs the Sparkle update feed (see below) |

### Sparkle update-signing key (one-time)

The release job signs each DMG with an EdDSA key and publishes `appcast.xml` as a release
asset; installed apps discover updates via
`https://github.com/ai-screams/Mara/releases/latest/download/appcast.xml`. The private key
exists only in the maintainer's Keychain (account `Mara` — the default account holds
Azimuth's key, do not reuse it) and in the `SPARKLE_ED_PRIVATE_KEY` environment secret;
only the public key ships in `App/Info.plist` (`SUPublicEDKey`).

```bash
# generate_keys comes from the SPM-resolved Sparkle artifact (never a separate download):
GEN_KEYS="$(find <DerivedData>/SourcePackages/artifacts -type f -name generate_keys | head -1)"
"$GEN_KEYS" --account Mara            # create key in Keychain, prints the public key
"$GEN_KEYS" --account Mara -x /tmp/k  # export private key…
gh secret set SPARKLE_ED_PRIVATE_KEY --env release --repo ai-screams/Mara < /tmp/k
rm -Pf /tmp/k                         # …and destroy the file immediately
```

⚠️ Losing this key means existing installs can no longer verify updates — the release
workflow's key-match gate will refuse to publish with a mismatched key, and recovering
requires shipping a new `SUPublicEDKey` via a manually-downloaded release.

### Enabling the automated release (one-time)

1. **Settings → Environments → New environment** → name it `release`. Add yourself as a
   **Required reviewer** (and optionally restrict deployment branches/tags).
2. Add the secrets above to that environment.
3. (Recommended) **Settings → Tags** → add a protection rule for `v*` so only maintainers can push
   release tags.
4. Push a tag (`git tag vX.Y.Z && git push origin vX.Y.Z`) → approve the run when prompted.

### Failed release recovery

`v*` tags are protected by the `protect-release-tags` ruleset (no update/delete, no bypass), so a
release that fails **after** its tag was pushed cannot reuse that tag. Recovery, in order of
preference:

1. **Bump to the next patch** (`vX.Y.Z+1`) and release again — burning a version number is cheap
   and keeps the immutability guarantee intact.
2. Break-glass only: temporarily disable the ruleset (**Settings → Rules → protect-release-tags**),
   delete the tag, re-enable the ruleset. Avoid this unless the version number must be preserved.

## First-launch note for users

The DMG opens Gatekeeper-clean (signed + notarized). Users drag **Mara** to Applications and launch
it — a menu-bar eye icon appears. No permission prompts. Optionally enable **Launch at Login** from
the menu.
