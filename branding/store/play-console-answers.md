# Play Console — App content answer sheet

Every declaration Play asks for before the Production track unlocks, with the
answer for Tetrofall v1.0.0 and the reason behind it. Filling these in is manual
console work; this file exists so the answers are **derived from the shipped
build** rather than recalled under time pressure, and so the next release can
diff against them.

Sources of truth used below: the permission list in the built release APK, the
plugin set in `pubspec.yaml`, and Google's own
[Mobile Ads SDK data disclosure](https://developers.google.com/admob/android/privacy/play-data-disclosure).

Keep this in sync with `website/privacy.html`. **Play audits the Data safety
form against the privacy policy**, and a contradiction between them is a
rejection cause.

---

## The SDK surface these answers come from

`google_mobile_ads` is the **only** third-party data-collecting SDK in the app.
There is no analytics, no crash reporting, no IAP, no login, no server.

Permissions actually merged into the release manifest (verified with
`aapt2 dump badging`):

| Permission | Source |
| --- | --- |
| `INTERNET`, `ACCESS_NETWORK_STATE` | ours — AdMob needs both |
| `com.google.android.gms.permission.AD_ID` | google_mobile_ads |
| `ACCESS_ADSERVICES_AD_ID` | google_mobile_ads (Privacy Sandbox) |
| `ACCESS_ADSERVICES_ATTRIBUTION` | google_mobile_ads (Privacy Sandbox) |
| `ACCESS_ADSERVICES_TOPICS` | google_mobile_ads (Privacy Sandbox) |
| `WAKE_LOCK`, `FOREGROUND_SERVICE` | google_mobile_ads |

---

## 1. Data safety

> ⚠️ **This is wider than "just the Advertising ID."** The release plan's §3.2
> said the form "stays short" because we ship no analytics of our own. That is
> the wrong test: the Mobile Ads SDK collects app interactions and diagnostics
> **itself**, whether or not you add analytics. Declaring only the ad ID would
> be under-declaring, which is what gets apps pulled.

**Preamble questions**

| Question | Answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (TLS — Google states this explicitly) |
| Do you provide a way for users to request that their data is deleted? | **Yes** — the contact email in the privacy policy |

**Data types — declare all four**

Every row: **Collected ✔ and Shared ✔**, purposes **Advertising or marketing +
Analytics + Fraud prevention, security and compliance**, and **Required** (not
"user can choose"), because the app does not offer a no-ads path.

| # | Category → Data type | What it actually is |
| --- | --- | --- |
| 1 | **Location → Approximate location** | Google derives coarse location from the IP address. The app holds **no** location permission and never sees GPS — declare it anyway, because the SDK transmits the IP. |
| 2 | **App activity → App interactions** | "User product interactions" reported to the ad SDK. |
| 3 | **App info and performance → Diagnostics** | Ad SDK performance/reliability data. |
| 4 | **Device or other IDs → Device or other IDs** | Android Advertising ID (AAID) **and** App Set ID. |

> On "is this data optional?": Google notes the ad ID is the one item a developer
> *could* suppress, by removing the `AD_ID` permission from the manifest. We do
> not do that (removing it would break ad serving), so for this app it is
> **required**, not optional. Do not tick "Users can choose whether this data is
> collected" — the UMP consent form governs *personalisation*, not collection.

---

## 2. Ads

| Question | Answer |
| --- | --- |
| Does your app contain ads? | **Yes** |

Non-negotiable: banner, interstitial, rewarded and app-open formats all ship.

---

## 3. Content rating (IARC questionnaire)

| Question | Answer |
| --- | --- |
| Category | **Game** |
| Violence / sexuality / language / controlled substances / crude humour | **No** to all — it is falling wooden blocks |
| Does the app share the user's location with other users? | No |
| Does the app allow users to interact or exchange content? | No |
| Does the app contain ads? | **Yes** |
| Does the app offer in-app purchases? | **No** |
| Gambling / simulated gambling | No |

Expected outcome: **Everyone / PEGI 3.** Answer the ads question honestly — a
rating obtained by omitting it is invalidated later.

---

## 4. Target audience and content

| Question | Answer |
| --- | --- |
| Target age groups | **13–15, 16–17, 18+** — tick nothing under 13 |
| Is your app appealing to children? | **No** |
| Store presence for children | N/A |

> ⛔ Selecting any under-13 bracket puts the app under the **Families Policy**,
> which bans personalised ads, restricts ad formats (app-open and interstitial
> rules tighten), and requires an AdMob reconfiguration. The wood-block art is
> deliberately not child-styled. Decision locked in §0.4.

---

## 5. Everything else in the checklist

| Section | Answer |
| --- | --- |
| **App access** | *All functionality is available without special access.* There is no login, no gate, no promo code. Say so explicitly or a reviewer will bounce it. |
| **News app** | No |
| **COVID-19 contact tracing / status** | No |
| **Government app** | No |
| **Financial features** | **None of the above** |
| **Health apps** | No |
| **Data deletion** | Provide the contact email. There is no account to delete; the policy explains uninstall + Auto Backup removal + ad-ID reset. |
| **Privacy policy URL** | `https://<domain>/privacy.html` — **blocked on §0.3** |
| **Store settings → category** | Games → **Puzzle** |
| **Store settings → tags** | Block puzzle, Casual, Offline, Brain games |

---

## 6. Advertising ID declaration (separate from Data safety)

Play asks a standalone question about advertising ID use since the Android 13
target requirement.

| Question | Answer |
| --- | --- |
| Does your app use advertising ID? | **Yes** |
| Purposes | **Advertising or marketing**, **Analytics** |

The `com.google.android.gms.permission.AD_ID` permission is present in the
manifest and must stay. Declaring "No" here while shipping that permission is an
automatic rejection.

---

## Blocked on Phase 0

Two answers cannot be finalised until the website is live and the domain chosen
(§0.3), because both are URLs on a domain that does not exist yet:

- Privacy policy URL
- Support / developer website URL

`support@nosleepstudios.com` — the contact address in `website/privacy.html` and
the data-deletion route — **must be a mailbox that actually receives mail before
submission.** A privacy policy whose contact address bounces is a failed data
deletion route. If `nosleepstudios.com` is not going to be registered, change the
address in `privacy.html`, `support.html` and the footer to one that works.
