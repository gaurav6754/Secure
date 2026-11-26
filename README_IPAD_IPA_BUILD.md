# SECURE AI v3.0.10 for iPad Pro (Native iPadOS + Built-In Desktop Browser)

## Why This Architecture Works on iPad Pro
On iPadOS, apps are sandboxed and cannot click inside Safari or Chrome. **SECURE AI for iPad Pro** solves this completely by embedding a **full Desktop-mode browser & Google search engine (`WKWebView`) directly inside the app** alongside the SECURE AI panel:

1. **Right side (Built-In Browser)**: Navigate directly to `https://secure.dord.gov.in/` (or search anything in the built-in URL/Google search bar), log in, and create/open your empty SECURE estimate.
2. **Left side (SECURE AI Panel)**: Upload your PDF (or generate an estimate using **100% AI** with native iPad voice dictation & `+ Files`), verify the rows, and press **START**.
3. **Direct DOM Automation**: Because the SECURE website runs inside the app, SECURE AI injects JavaScript directly into the page DOM (no fragile pixel clicking) to add headings, select Bihar MGNREGA `54` / `54-TM` subheads, search and add SOR codes, enter measurements/deductions, add Lump Sums, and run **Verify & Fix Error (Delete & Re-Add)** with SweetAlert2 auto-confirmation.

---

## How to Build the `.ipa` File

### Option A: Build `.ipa` for FREE Without a Mac (GitHub Actions — Recommended)
1. Unzip `SECURE_AI_iPad_v3_0_10_IPA_Project.zip`.
2. Create a new GitHub repository (can be **Private**) at `https://github.com/new` and upload all extracted files (including the `.github/workflows/build-ipa.yml` folder).
3. Open your repository's **Actions** tab → click **Build SECURE AI iPad IPA** → click **Run workflow**.
4. Wait ~2–3 minutes for the macOS runner to finish, then download **`SECURE_AI_iPad_v3.0.10_IPA`** from the **Artifacts** section at the bottom of the run.
5. Install the `.ipa` on your iPad Pro using:
   - **Sideloadly** (Windows/Mac — easiest with a free Apple ID),
   - **AltStore** / **SideStore**, or
   - **TrollStore** (if supported on your iPadOS version).

### Option B: Build Directly on a Mac with Xcode
```bash
brew install xcodegen
xcodegen generate
open SECURE_AI_iPad.xcodeproj
```
Select your iPad Pro as the run destination, pick your Apple Team under **Signing & Capabilities**, and press **Run (`⌘R`)** or **Product → Archive** to export a signed `.ipa`.
