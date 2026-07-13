# Sparkle signing

1. Generate keys (Keychain + export for CI):

```bash
./scripts/generate-sparkle-keys.sh
```

macOS may prompt for Keychain access — allow it.

2. Script writes:
- `signing/sparkle_public_ed_key.txt` (safe to commit)
- `signing/ed25519-privkey.txt` (**never commit**)
- updates `OPS_SPARKLE_PUBLIC_ED_KEY` in the Xcode project

3. Add private key file contents as GitHub Actions secret:

- Name: `SPARKLE_PRIVATE_KEY`
- Value: entire contents of `signing/ed25519-privkey.txt`

4. Never commit `signing/ed25519-privkey.txt` or `*.pem` private material.

## Ad-hoc distribution (current CI)

CI signs with `CODE_SIGN_IDENTITY="-"` and `signing/Ops-adhoc.entitlements`
(`com.apple.security.cs.disable-library-validation`). That is required so Sparkle’s
Team ID does not crash the app under Hardened Runtime.

When you move to **Developer ID + notarization**, remove that entitlement and sign
the whole app (including Sparkle) with your Team ID instead.

## Gatekeeper / notarization (optional but recommended)

Ad-hoc builds (`CODE_SIGN_IDENTITY="-"`) work for CI and testing, but users may need right-click → Open.

For production: Developer ID + notarize the DMG/ZIP, then staple.
