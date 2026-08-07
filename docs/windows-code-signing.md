# Windows code signing — killing the "Unknown publisher" warning

**Problem:** installing the Windows build shows *"Unknown publisher"* (or a
SmartScreen "Windows protected your PC" block).

**Why:** the installer and every bundled `.exe` ship **unsigned**. Windows
shows the publisher name only when the file carries an Authenticode signature
chained to a certificate authority Windows trusts. No signature = "Unknown
publisher".

It is **not** a registration on some Microsoft portal. You need a
**code-signing certificate** (and optionally build SmartScreen reputation,
see the FAQ). The signing pipeline is already wired into the build; this doc
covers getting the certificate and plugging it in.

## 1. Get a code-signing certificate

Three real options. Skip "self-signed" certificates — Windows does not trust
them, so they do NOT remove the warning.

| Option | Cost | Time | Notes |
| --- | --- | --- | --- |
| **Azure Trusted Signing** (recommended) | ~USD 9/mo | Minutes–hours | Microsoft's cloud signing. No USB token. Standard cert is enough for Open Source software; gets "Microsoft-issued" trust quickly. Best for CI. |
| **OV code-signing cert** (DigiCert, Sectigo, SSL.com) | USD 200–400/yr | 1–3 business days (identity verification) | Classic route. You are org-verified, then sign locally or via cloud HSM. |
| **EV code-signing cert** | USD 300–500/yr | 1–5 days (hardware token required) | Instant SmartScreen reputation while valid; most expensive, often overkill. |

**For a free/open-source project** also check Microsoft's *Trusted Signing*
free tier availability and GitHub's Open Source program discounts — but
expect to pay for a cert one way or another; there is no way to remove the
warning without a real certificate.

> Azure Trusted Signing notes: create a Trusted Signing Account → certificate
> profile (identity type "Organization" or "Public" for OSS) → export the
> certificate public key to a `.cer`, then use the
> `azure/trusted-signing-action` GitHub Action (or AzureSignTool locally) in
> CI. The output is a `.pfx`-equivalent signing identity.

## 2. Wire it into the repo

The build already supports signing; it activates when two things exist:

1. **Certificate file** — a `.pfx` containing your code-signing cert +
   private key. Keep it base64-encoded as a **GitHub secret**
   `WIN_SIGN_CERT`:
   ```sh
   base64 -i cert.pfx -o cert.b64   # then paste cert.b64 contents into the secret
   ```
2. **Password secret** — `WIN_SIGN_PWD` = the .pfx password.

`release.yml` (build-windows job) decodes `cert.b64` → `cert.pfx` and passes
`SIGN_PFX`/`SIGN_PWD` to `scripts\build_windows.bat`, which then:

1. Signs **every** bundled EXE (compresstor.exe + engine\engine_cli.exe +
   helpers) with an RFC 3161 timestamped SHA-256 signature (Stage 4) —
   SmartScreen inspects the installed exes, not just the setup.exe;
2. Builds the Inno Setup installer (Stage 6);
3. Signs and verifies the installer itself.

### Local Windows testing (without pushing)

```bat
set SIGN_PFX=C:\certs\compresstor.pfx
set SIGN_PWD=yourpassword
scripts\build_windows.bat
```

Then confirm with:

```bat
signtool verify /pa /v release\Compresstor-1.1.8-windows-setup.exe
```

Expect "Verified: Is Signed" + a chain ending in a trusted root. Also check
the installed `compresstor.exe` in File Explorer → Properties → Digital
Signatures tab.

## 3. GitHub Actions (Azure Trusted Signing alternative)

If you use Azure Trusted Signing instead of a `.pfx`, replace the
"Decode signing certificate" step in `release.yml` with:

```yaml
- uses: azure/trusted-signing-action@v0
  with:
    endpoint: https://eus.codesigning.azure.net
    trusted-signing-account-name: ${{ secrets.AZ_SIGN_ACCOUNT }}
    certificate-profile-name: ${{ secrets.AZ_SIGN_PROFILE }}
    files: |
      release/Compresstor-*-windows-setup.exe
    signing-certificate: ${{ secrets.AZ_SIGN_CERT_B64 }}
```

(Set `endpoint` to your account's region endpoint; export the profile's
public cert to base64 and store as `AZ_SIGN_CERT_B64`.) With this route you
do not need `SIGN_PFX`/`SIGN_PWD` — adjust `build_windows.bat` accordingly
(the EXEs still need signing; use AzureSignTool or the action with the
unpacked app folder paths).

## FAQ

**Does signing fully remove SmartScreen's blue "Windows protected your PC"?**
Not always. SmartScreen reputation is separate from the signature: a brand-new
certificate on an app with few downloads can still show the blue dialog
("More info → Run anyway") until enough people run it and it isn't reported.
"Unknown publisher" (the red/gray dialog) disappears as soon as the signature
is valid; the blue reputation dialog fades over time/downloads. An EV cert
skips the reputation wait while valid.

**Does the "More info → Run anyway" path hurt us?** No — one-time click, and
reputation builds from there.

**Do I need to sign the update zips too?** The zip is not executed, so no.
Only the installer and the bundled EXEs matter.

**Why is the publisher "ejjat0909" in the installer but "Unknown" before?**
The Inno script already sets `AppPublisher`. Once the files are signed, both
the installer and the app show the certificate's subject instead.
