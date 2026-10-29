# Rivalink - Sports Matchmaking Platform

## Overview

Rivalink is a full-stack sports matchmaking platform built with **Flutter** (mobile app) and **Django REST Framework** (backend). Users can organize and join matches, create and manage teams, participate in leagues with Elo/points ranking, chat with teammates and match participants, and track their performance.

---

## What's Implemented

### ✅ Core Features

1. **User Authentication**
   - Sign up / Login with email and phone
   - Session management (token-based)
   - Profile editing with photo upload
   - Location on signup and edit profile

2. **Match System**
   - Create matches (sport, date, time, location, price, max players)
   - Join/Leave matches
   - Match details with participant list
   - Search and filter matches
   - Match recommendations ("Recommended For You") ranked by sport, location,
     urgency, reliability, collaborative filtering and (once trained) propensity
   - Match history

3. **Team Management**
   - Create teams with sport, location, max members
   - Request to join / Join teams
   - Team members roster
   - Team owner controls (approve/reject join requests, remove members)
   - Team recruitment (seeking players toggle)
   - **Team Chat** — members can chat within their team

4. **League System**
   - Browse upcoming leagues
   - **Join leagues** with a team selector (picks from your teams)
   - **Create leagues** (name, sport, format, max teams, entry fee, prize, location, start date)
   - **League standings** — sorted by points → goal difference → goals for, with P/W/D/L columns
   - Full league details view with header, info card, and standings table

5. **Ranking System**
   - **Individual Glicko-2 ratings** per sport (initial 1200, RD 350, volatility 0.06)
   - **Team ranking** with points-based league standings
   - Rankings screen with tab toggle (Individual / Teams) and sport filter
   - User profile shows per-sport rating with W/L/D

6. **Match Results & Scorekeeping**
   - Record match outcomes (pickup, 1v1, team vs team)
   - MVP selection for pickup matches
   - **Team group assignments** (A/B) for team sports with individual Glicko-2
   - Score entry (e.g. "3-2")
   - Auto-computes rankings after result submission

7. **In-Match Chat**
   - Chat with match participants
   - Real-time message display with bubble styling
   - Notifications to all other participants when a message is sent
   - Error handling and loading states

8. **Notifications**
   - Notification bell with red badge (polls every 30s)
   - Match joined/left/cancelled notifications
   - Chat message notifications (match and team)
   - Mark all as read

9. **Player Ratings**
   - Rate players after matches (1-5 stars + comments)
   - View user ratings on profile

10. **User Profile & Stats**
    - Profile editing with photo
    - Stats: matches played, wins, losses, teams owned, leagues joined, avg rating
    - Per-sport Elo ratings with W/L/D breakdown

11. **Venue Management**
    - Create, update, delete venues (name, description, sports, price, capacity, amenities, hours)
    - Browse venues with sport/price/location filters
    - Book venues by date/time slot
    - View venue bookings and availability
    - Rate venues

12. **Tournament System**
    - Create tournaments (name, sport, format, prize pool, entry fee, max teams)
    - Edit and delete tournaments
    - Register teams for tournaments
    - Start tournaments with bracket generation
    - Update tournament match results, auto-advance winners

13. **Referee System**
    - Create referee profiles with experience and certifications
    - Browse available referees
    - Book referees for matches
    - Rate referees after booking

14. **Favorites**
    - Favorite teams
    - View favorited teams

---

## 💰 Business Model — How Rivalink Makes Money

> All prices in **ETB**. Rates live in `backend/core/monetization.py` and every
> fee is written to the `PlatformTransaction` ledger.

### The 5 wallets
1. **Players** — micro-fees + Premium
2. **Hosts / organizers** — per-match host fee
3. **Venues** — booking commission
4. **Referees** — booking commission
5. **Brands** — branded leagues + ads (the biggest cheques)

### Revenue streams (turn on in this order)

| # | Stream | Rate / Price | Example |
|---|--------|--------------|---------|
| 1 | **Venue booking commission** | 10% of booking | Pitch **Br 2,000 / 2-hour slot** → **Br 200** |
| 2 | **Host fee** (free users) | Br 20 / hosted match | 1,500 hosts/mo → **Br 30,000/mo** |
| 3 | **Premium subscription** | **Br 100 / month** | 500 subscribers → **Br 50,000/mo** |
| 4 | **Referee commission** | 10% of referee fee | Referee Br 500 → **Br 50** |
| 5 | **Tournament entry cut** | 12% of entry fee | 16 teams × Br 1,500 = Br 24,000 → **Br 2,880** |
| 6 | Featured / boosted venue listing | Br 1,500–3,000 / mo | 8 venues → **Br 16,000/mo** |
| 7 | **Branded league sponsorship** | Br 100,000–300,000 / season | 1 deal → **Br 150,000** |
| 8 | In-app ads / sponsored placement | Br 20,000–50,000 / mo | — |
| 9 | Payment take rate (Chapa/Telebirr) | 1–2% | — |
| 10 | Merch / kit drops | 20–30% margin | — |

### ✅ Implemented (transactional)

- `PlatformTransaction` ledger — `kind`, `amount`, `currency`, `payer`, `reference`, `status`, `note`
- Venues are booked in **2-hour slots** (minimum 2 hours — nobody books a single hour)
- **Venue booking → 10% commission** recorded on every direct booking
- **Match field booking → flat Br 250 service fee** (only when booked)
- **Host fee Br 20** recorded on every hosted match (Premium hosts exempt)
- **Referee booking → 10% commission**
- **Tournament registration → 12% entry cut**
- **Premium Br 100/mo** recorded on a successful Chapa webhook
- **Match-share escrow** held per player; booked matches pay the venue from the pot
- **Venue payable** — the venue owner’s payee balance is credited with the field price
- **Match pot and withdrawals** — after booking, a player can withdraw; the spot stays funded
- **Player credit** — leftover pot surplus is split equally as in-app credit
- **Host payouts** — payees request withdrawals; staff mark them paid with a reference
- Endpoints: `GET /api/revenue/summary/` (staff only), `GET /api/revenue/me/`

### Host earnings & payouts

`HostAccount` is the payee account. A booked match credits the **venue owner** with
a `venue_release` entry. Hosts get a `match_release` entry only for matches that
do not use a venue pot (the legacy flow).

- **Payees** open **Profile → Host earnings** (`/host-earnings` in the app) to see
  available, pending and paid-out balances, the signed ledger, and payout history.
- A payout request moves money from **available → pending**. Minimum Br 100; one
  request in progress at a time. Payees can cancel a request before review.
- **Staff** review payouts in Django admin or via
  `POST /api/host/payouts/<id>/review/` with `action=paid` plus the bank/Telebirr
  `reference`, or `action=rejected` (funds return to available).
- **Paid** means the transfer left Rivalink and the reference is recorded. Actual
  bank/Telebirr movement is still done manually by staff.
- Late host cancellations claw back released money, which can leave the balance
  negative until future releases cover it.

Endpoints:

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/host/earnings/` | Balances, ledger, payouts |
| GET/POST | `/api/host/payouts/` | List payouts / request one |
| POST | `/api/host/payouts/<id>/cancel/` | Payee cancels a requested payout |
| POST | `/api/host/payouts/<id>/review/` | Staff marks paid or rejected |

### Match pot, withdrawals and player credit

A match with a venue uses a pooled pot instead of paying the host.

1. The host is a player too and pays one share. Paying reserves the venue slot
   (the calendar shows **Reserved**, not Booked).
2. Other players join and pay the same share.
3. The target is **field price + Br 250 Rivalink service fee** (the fee is shown
   as a separate line and is only earned when booking succeeds).
4. The host can request booking once **every active player has paid**, the
   **minimum player count** is met, and **collected ≥ target**.
5. Every player must confirm before the field is booked.
6. When booked: the venue owner is credited the field price, the Br 250 service
   fee is recorded as collected, and any surplus stays in the match pot.

After booking:

- **No refunds.** A player who can’t make it uses **Withdraw from match**.
- The withdrawn share opens a **funded spot**. The next player joins free.
- If the host withdraws, organizer passes to another active player; the match
  stays booked.
- At kickoff, any remaining pot surplus is split equally as **player credit**.
  If there is no surplus, no credit is created. The 36-hour deadline auto-cancels
  under-filled, unbooked matches and refunds everyone.
- Before booking, a player who leaves gets a full refund. A host who cancels
  before booking loses **20% of his own share**; everyone else is refunded.

Player credit is tracked in the `PlayerCreditAccount` ledger and shown in
**Profile → Credits** (`GET /api/credits/`). Credit is applied automatically
when paying a match share: partial credit reduces the Chapa amount, and full
credit skips checkout entirely. If the share is later refunded before booking,
the credit portion returns to the credit balance.

Stale unpaid venue reservations are released after one hour by the lifecycle
job, and under-filled/unfunded matches are cancelled at the 36-hour deadline.

Match endpoints:

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/matches/<id>/pay/` | Pay your match share |
| POST | `/api/matches/<id>/booking-request/` | Host requests field booking |
| POST | `/api/matches/<id>/booking-confirm/` | Player confirms booking |
| POST | `/api/matches/<id>/withdraw/` | Withdraw after booking |
| GET | `/api/credits/` | Credit balance + history |

### Worked projection — 5,000 monthly users

| Stream | Math | ETB/mo |
|---|---|---|
| Venue commission | 2,000 × Br 2,000 × 10% | 400,000 |
| Premium (10% pay) | 500 × Br 100 | 50,000 |
| Host fees | 1,500 × Br 20 | 30,000 |
| Referee commission | 300 × Br 500 × 10% | 15,000 |
| Featured listings | 8 × Br 2,000 | 16,000 |
| Tournaments | 4 × Br 24,000 × 12% | 11,520 |
| Brand league (1/mo) | flat | 150,000 |
| **Total** | | **≈ Br 672,520/mo** |

Brand money + venue commission ≈ **82%** of revenue — subscriptions alone are ~Br 50k.

### Ethiopia-specific notes
- **Payments**: integrate **Chapa** (aggregates Telebirr, CBE Birr, M-PESA, cards). Cards are rare — mobile money is king. Payouts to venues/referees via Telebirr.
- **Cash economy**: many venues take cash → offer **"pay at venue" + a small prepaid booking fee (Br 20–50)** to hold the slot.
- **Price sensitivity**: micro-fees (Br 10–30) beat big subscriptions. Keep Premium at Br 100.
- **Disintermediation**: players/venues will try to cut the platform out — beat it with matchmaking, Elo/rankings, verified venues, no-show protection, dispute handling.
- **Taxes**: budget **15% VAT** (if VAT-registered) or **2% turnover tax** (small business).

### What to start with
1. **Venue booking commission** — earns on day one, tied to value delivered
2. **Premium** (Br 100/mo — already wired)
3. **Referee + tournament cuts** — flows already exist
4. **Brand leagues** — once you can show traction numbers

---

## Premium Subscription System

### 🆓 Free Tier
| Feature | Limit |
|---------|-------|
| Join matches | Unlimited |
| Host matches | 2 per month |
| Create teams | 1 team |
| Join teams | 1 team |
| Get ranked (Elo) | ❌ No |
| Leagues | ❌ No |
| Team chat | ✅ Yes |
| Match chat | ✅ Yes |
| View rankings | ✅ Can browse |

### 💎 Premium (Br 100/mo)
| Feature | Benefit |
|---------|---------|
| Host matches | Unlimited |
| Create teams | Unlimited |
| Join teams | Unlimited |
| Get ranked (Elo) | ✅ Yes — Elo tracks your performance |
| Leagues | ✅ Yes — all team members need premium |
| Priority listing | Appear first in search results |
| Premium badge | Gold badge on profile |
| Advanced stats | Win trends, form guide |
| Ad-free | No promotions |

### Implementation Plan

#### Backend — User Model
```python
# Add to UserProfile model
is_premium = models.BooleanField(default=False)
premium_expires = models.DateTimeField(null=True, blank=True)
```

#### Backend — Entitlement Checks

**1. Host match limit (2/month for free)**
```python
def can_host_match(user):
    if user.profile.is_premium:
        return True
    this_month = timezone.now().replace(day=1)
    count = Match.objects.filter(
        organizer=user,
        created_at__gte=this_month
    ).count()
    return count < 2
```

**2. Team creation/join limits**
```python
MAX_FREE_TEAMS_CREATED = 1
MAX_FREE_TEAMS_JOINED = 1

def can_create_team(user):
    if user.profile.is_premium:
        return True
    return Team.objects.filter(owner=user).count() < MAX_FREE_TEAMS_CREATED

def can_join_team(user):
    if user.profile.is_premium:
        return True
    return TeamMember.objects.filter(user=user).count() < MAX_FREE_TEAMS_JOINED
```

**3. Elo ranking — free users don't get rated**
```python
def _compute_rankings(match, result):
    participants = MatchParticipant.objects.filter(match=match)
    for p in participants:
        # Skip free users — they play but don't affect rankings
        if not p.user.profile.is_premium:
            continue
        # ... existing Elo calculation
```
- Free users can still *play* in any match, but their performance doesn't change their (hidden) Elo.
- Their profile shows "Upgrade to Premium to see your ranking" instead of a number.
- The rankings leaderboard only includes premium users.

**4. League join — all team members must be premium (Strict model)**
```python
def join_league(request):
    team_id = request.data.get('team_id')
    team = Team.objects.get(id=team_id)
    
    # Strict: every single team member must be premium
    non_premium = TeamMember.objects.filter(
        team=team
    ).exclude(
        user__profile__is_premium=True
    ).count()
    
    if non_premium > 0:
        return Response({
            'error': 'All team members need Rivalink Premium to join a league'
        }, status=status.HTTP_402_PAYMENT_REQUIRED)
    
    # ... proceed with league join
```
- This creates social pressure: the team collectively upgrades or nobody plays.
- Alternative (Softer): only the team owner needs premium.

**5. League creation — organizer must be premium**
```python
def create_league(request):
    if not request.user.profile.is_premium:
        return Response({
            'error': 'Only Premium users can create leagues'
        }, status=status.HTTP_402_PAYMENT_REQUIRED)
```

#### Flutter — Upsell Screens

- **Gated action → Premium prompt**: When a free user hits a limit (e.g. tries to host a 3rd match), show a bottom sheet:
  ```
  ┌──────────────────────────────┐
  │  🔒 Upgrade to Premium       │
  │                              │
  │  You've used all 2 free      │
  │  hosts this month.           │
  │                              │
  │  [See Plans]  [Not Now]      │
  └──────────────────────────────┘
  ```
- **Rankings placeholder**: On profile, show `--` or a lock icon next to Elo with "Upgrade to get ranked"
- **League join**: When tapping "Join League", first check all team members' premium status before showing the join confirmation

#### Payment Integration Required
- **Mobile money** (Ethio Telecom, Safaricom) — primary for Ethiopian market
- **Google Play Billing** — for subscription management on Android
- **Server-side receipt validation** — to prevent fraud

---

## Brand Sponsorship Model

### How Rivalink Makes Money from Brand Partnerships

Big brands (Fanta, Coca-Cola, Pepsi, banks, betting companies) have marketing budgets for community sports. They pay Rivalink to host branded leagues/tournaments — you get paid regardless of how many users are premium.

### Structure Options

#### 1. Flat Sponsorship Fee (Best for Rivalink)
Brand pays a flat fee to run the league under their name. Prize pool is separate.

| Item | Amount |
|------|--------|
| Brand pays Rivalink | **100,000 ETB** |
| Prize pool (brand-funded) | 50,000 ETB |
| Rivalink keeps | 100,000 ETB |
| 256 players wear branded jerseys for 8 weeks | — |

#### 2. Management Fee (20-30% cut)
| Item | Amount |
|------|--------|
| Brand total budget | 200,000 ETB |
| Rivalink management fee | **50,000 ETB** (25%) |
| Prize pool | 100,000 ETB |
| Operations (referees, venue, equipment) | 50,000 ETB |

#### 3. Entry Fee + Brand Top-Up (Recurring)
Teams pay entry, brand matches or tops up the prize pool.

| Item | Amount |
|------|--------|
| 32 teams × 1,000 ETB entry | 32,000 ETB |
| Brand prize top-up | 50,000 ETB |
| Rivalink takes 15% of entry fees | 4,800 ETB |
| Flat sponsorship fee | 30,000 ETB |
| **Total to Rivalink** | **~35,000 ETB per season** |

### Pitch Deck for Brands

```
Rivalink x [BRAND] LEAGUE

Deliverables:
- "[Brand] Premier League" branding across app (banners, match pages)
- 8-week season, 32 teams (256 active players)
- Weekly social media highlights (IG/TikTok)
- Finals event at venue with photo/video coverage
- Minimum 50,000 impressions across platform

Investment:
- Prize pool: 50,000 ETB (branded as "[Brand] Cup")
- Sponsorship fee: 100,000 ETB

Value to Brand:
- 256 active athletes wearing branded gear weekly
- Organic social reach: players share → friends see brand logo
- Finals event with crowd + shareable content
- Positioned as "champion of local Ethiopian sports"
- Cost per engaged user: ~3-5 ETB vs 30-50 ETB for billboards
```

### Revenue Projection at Scale (5,000 users)

| Source | Monthly |
|--------|---------|
| Premium subscriptions (10% conversion) | 50,000 ETB |
| Branded league sponsorships (2 per month) | 200,000 ETB |
| Tournament entry fees (15% cut) | 15,000 ETB |
| Featured match listings | 5,000 ETB |
| Venue commissions | 8,000 ETB |
| **Total** | **~278,000 ETB/mo (~$4,800)** |

Brand sponsorships are the **real revenue multiplier** — one branded league can pay more than all subscriptions combined.

---

## What's Missing

### 🔴 High Priority
- **Stable production `SITE_URL` + separate Chapa webhook secret** (the dev tunnel is not reliable)
- **Automated venue/referee payouts** (payables and staff-reviewed payouts exist; bank/Telebirr transfer is manual)

### 🟡 Medium Priority
- **Dispute resolution** (conflict process, refunds)
- **Advertising system** (banners, sponsored content)
- **Credit applied to venue bookings** (currently applied to match shares only)

### 🟢 Low Priority
- **Corporate event management**
- **Insurance/liability** (ToS, waivers)
- **Data analytics monetization**

---

## Security Hardening

### ✅ Rate Limiting
| Throttle | Default (dev) | Production | Applied To |
|----------|--------------|------------|------------|
| `AuthRateThrottle` | 20/hr | 5/hr | signup, login |
| `CreateRateThrottle` | 30/hr | 10/hr | create_team, create_match, create_tournament, etc. |
| `SensitiveWriteThrottle` | 30/hr | 10/hr | match_result, book_venue, register_team_tournament, update_match_result, edit/delete league/tournament/venue, upload_profile_image |
| Global `AnonRateThrottle` | 20/hr | 20/hr | All anonymous requests |
| Global `UserRateThrottle` | 200/hr | 200/hr | All authenticated requests |

Rates configurable via `.env`: `RATE_AUTH`, `RATE_CREATE`, `RATE_SENSITIVE`.

### ✅ Input Validation & Sanitization (`core/validators.py`)
- **Email**: RFC-like regex + max 254 chars
- **Phone**: Ethiopian format `(+251|0)XXXXXXXXX`
- **Password**: Min 8 chars, requires uppercase + lowercase + digit
- **Strings**: Max-length enforcement per field (title: 200, description: 5000, etc.)
- **Integers**: Range-bounded (max_players: 2-100, capacity: 0-100000, etc.)
- **Decimals**: Range-bounded (entry_fee: 0-999999, slot_price: 0-999999)
- **Enums**: Whitelist validation (sport, format, result type, team role, etc.)
- **Dates**: ISO 8601 parsing with `validate_date_iso`
- **Booleans**: Proper coercion via `validate_boolean`
- **HTML/XSS**: `sanitize_text()` strips all HTML tags via Django's `strip_tags`
- **Image uploads**: Extension check + MIME type + **magic byte verification** (JPEG/PNG/GIF/WebP) + 5MB size limit

### ✅ Secure API Key Handling
- **`SECRET_KEY`** loaded from `DJANGO_SECRET_KEY` env var via `python-dotenv`
- **`.env`** gitignored — never committed to repo
- **Production-only settings** enabled when `DEBUG=False`:
  - `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE` (HTTPS-only)
  - `SECURE_BROWSER_XSS_FILTER`, `SECURE_CONTENT_TYPE_NOSNIFF`
  - `SECURE_HSTS_SECONDS` (31536000), `SECURE_SSL_REDIRECT`
  - `X_FRAME_OPTIONS = 'DENY'`
  - JSON-only renderer (no browsable API)
- **Proxy support**: `SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')` for ngrok/reverse proxy
- **CSRF**: `CSRF_TRUSTED_ORIGINS` configurable via env var
- **Database**: `DATABASE_URL` env var support via `dj-database-url` (falls back to SQLite)
- **Upload limits**: `DATA_UPLOAD_MAX_MEMORY_SIZE` = 5MB, `FILE_UPLOAD_MAX_MEMORY_SIZE` = 5MB
- **Field limits**: `DATA_UPLOAD_MAX_NUMBER_FIELDS` = 100
- **Password validators**: Django built-in (min length 8, common password check, etc.)

### ✅ Flutter Token Storage
Auth tokens moved from `SharedPreferences` (plaintext) to `flutter_secure_storage` (Android Keystore / iOS Keychain).

### ✅ Token Expiry & Rotation
- `ExpiringTokenAuthentication` (`core/auth.py`) — tokens expire after **30 days** (`TOKEN_TTL_DAYS`; `0` disables)
- **Change password** (`POST /api/auth/password/change/`) verifies the current password and **rotates the token** → all other devices are signed out
- **Log out all devices** (`POST /api/auth/logout-all/`) invalidates the token everywhere

### ✅ Audit Logging
- `AuditLog` model (`core/models.py`) + `core/audit.py` — records user, action, status, IP, user-agent
- Wired into: **login** (ok/failed), **signup**, **logout**, **password change**, **logout-all**, **password reset**, and the **payment webhook** (including **invalid-signature** attempts)
- Structured logging via the `rivalink.security` logger

### ✅ Password Reset (secure)
- `POST /api/auth/password/reset/request/` — always returns a **generic** response (no email enumeration); issues a `secrets`-based 6-digit code with a **30-minute expiry**, delivered by SMS
- `POST /api/auth/password/reset/confirm/` — constant-time comparison, throttled (5/hr), invalidates all sessions on success

### ✅ Enumeration & Admin Hardening
- Signup returns a **generic** error (no "email already exists" leak)
- Admin path is env-configurable (`ADMIN_URL`, default `admin/`)
- **Dependabot** configured for pip + pub + GitHub Actions (`.github/dependabot.yml`)

### 🔜 Known gaps (deferred)
- **SMS/OTP hardening** — throttle `send_phone_code`, validate the phone, `secrets`-based codes (deferred until SMS is live)
- **Media signed URLs** — profile/venue images are currently public-by-URL
- **FCM HTTP v1** — push still uses the legacy server key

---

## Technical Stack

### Frontend (Flutter)
- **Framework**: Flutter 3.x
- **State Management**: setState + SessionController with error state
- **HTTP Client**: `http` package with timeout handling
- **Storage**: `flutter_secure_storage` (auth tokens), `shared_preferences` (cache/onboarding)
- **UI**: Material Design 3, `google_fonts`
- **API Config**: Centralized `ApiConfig.baseUrl` — all services use a single configurable base URL
- **Utilities**: `formatters.dart` (date/number formatting), `sport_utils.dart` (icons/gradients)

### Backend (Django)
- **Framework**: Django 6.x + Django REST Framework
- **Authentication**: Token-based (DRF `Token` model)
- **Rate Limiting**: DRF throttling — Auth (5/hr), Write (10/hr), Sensitive (10/hr)
- **Database**: SQLite (dev) / PostgreSQL via `DATABASE_URL` env var (`dj-database-url`)
- **CORS**: `django-cors-headers`
- **Secrets**: `python-dotenv` — all keys from environment, `.env` gitignored
- **Proxy**: `SECURE_PROXY_SSL_HEADER` configured for ngrok/reverse proxy
- **Image Validation**: Magic byte verification for uploads (JPEG/PNG/GIF/WebP)

### Infrastructure (Dev)
- **Tunnel**: ngrok for development
- **API URL**: Configurable via `ApiConfig.baseUrl` in Flutter, ngrok URL set in `.env`

---

## Scaling & Production Infrastructure

### Current Bottlenecks

| Issue | Why It Breaks | Hits At |
|-------|---------------|---------|
| **SQLite** | Single-writer lock — concurrent writes fail | ~50 concurrent users |
| **Synchronous rankings** | `_compute_rankings()` blocks the request thread | ~100 concurrent users |
| **30s polling** | Every client hits `/notifications/` every 30s | ~500 users |
| **Images from Django** | Dev server ties up workers serving uploads | ~100 concurrent users |
| **ngrok** | Bandwidth cap (~1-2 MB/s), latency overhead | ~50 users |

### Production VPS Options

| Provider | Specs | Price | Notes |
|----------|-------|-------|-------|
| **Hetzner** | 2 vCPU, 4GB RAM, 40GB SSD | ~$5/mo (290 ETB) | Best value globally |
| **DigitalOcean** | 2 vCPU, 2GB RAM, 50GB SSD | ~$12/mo (700 ETB) | Simple, well-documented |
| **Contabo** | 4 vCPU, 8GB RAM, 200GB SSD | ~$7/mo (400 ETB) | Overkill specs for price |
| **Linode (Akamai)** | 2 vCPU, 4GB RAM, 80GB SSD | ~$12/mo (700 ETB) | Good performance |

**Recommended: Hetzner CX22** — $5/mo, serves 1,000-2,000 concurrent users.

### Production Stack

| Component | Purpose | Cost |
|-----------|---------|------|
| **PostgreSQL** | Replace SQLite — handles concurrent writes | Free |
| **Redis** | Background tasks (Celery) + caching rankings/leagues | Free |
| **Nginx + Let's Encrypt** | Reverse proxy, static files, HTTPS (auto-renewing) | Free |
| **Gunicorn** | Production WSGI server for Django | Free |
| **Cloudinary (free tier)** | Image hosting, offloads Django from serving files | Free |
| **Domain** | e.g. `api.Rivalink.et` | ~$3/yr |
| **VPS** | Hetzner CX22 | $5/mo |
| **Total monthly** | | **~$10/mo (580 ETB)** |

### Fix Priority Order

| # | Fix | Impact |
|---|-----|--------|
| 1 | SQLite → PostgreSQL | Removes write lock bottleneck |
| 2 | ngrok → VPS with static IP + HTTPS | Removes latency, bandwidth cap |
| 3 | Background task queue (Celery + Redis) | Rankings, notifications off the request thread |
| 4 | Cloud image hosting (Cloudinary/S3) | Offloads image serving from Django |
| 5 | Redis caching | Rankings, leagues, matches served from cache |
| 6 | WebSockets (Django Channels) | Real-time notifications without polling |

---

## Project Structure

```
Rivalink/
├── backend/
│   ├── core/
│   │   ├── models.py          # Django models (User, Match, Team, League, etc.)
│   │   ├── views.py           # All API endpoints
│   │   ├── urls.py            # URL routing
│   │   ├── elo.py             # Elo calculation utility
│   │   ├── validators.py      # Input validation, sanitization, throttle classes
│   │   └── migrations/        # DB migrations (0022 latest)
│   ├── Rivalink_backend/
│   │   └── settings.py        # Django settings (env-based config)
│   ├── db.sqlite3             # SQLite database
│   ├── .env                   # Environment variables (gitignored)
│   ├── .gitignore
│   ├── requirements.txt
│   └── manage.py
├── Rivalink/
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/
│   │   │   ├── data/
│   │   │   │   ├── models/        # Dart data models
│   │   │   │   ├── repositories/  # AppRepository (service wrapper)
│   │   │   │   └── services/      # API service classes
│   │   │   ├── navigation/        # AppRoutes
│   │   │   ├── state/             # SessionController
│   │   │   ├── theme/             # RivalinkTheme
│   │   │   └── utils/             # Formatters, sport_utils
│   │   └── ui/
│   │       ├── screens/           # All screens
│   │       └── widgets/           # Reusable widgets
│   └── pubspec.yaml
└── README.md
```

---

## Running the App

### Prerequisites
- Python 3.8+
- Flutter SDK
- ngrok (for backend tunnel)

### Backend Setup
```bash
cd backend
cp .env.example .env       # Create env file (or use existing .env)
python -m pip install -r requirements.txt
python manage.py runserver
# In separate terminal:
ngrok http 8000
# Update ngrok URL in backend .env and Flutter ApiConfig.baseUrl if it changes
```

### Environment Variables
| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DJANGO_SECRET_KEY` | Yes | — | Django secret key |
| `DEBUG` | No | `False` | Debug mode |
| `ALLOWED_HOSTS` | No | `localhost,127.0.0.1` | Comma-separated allowed hosts |
| `CORS_ALLOWED_ORIGINS` | No | — | Comma-separated CORS origins |
| `CSRF_TRUSTED_ORIGINS` | No | — | Comma-separated trusted origins |
| `DATABASE_URL` | No | SQLite | PostgreSQL connection string |
| `RATE_AUTH` | No | `5/hour` | Auth rate limit |
| `RATE_CREATE` | No | `10/hour` | Create rate limit |
| `RATE_SENSITIVE` | No | `10/hour` | Sensitive write rate limit |
| `TOKEN_TTL_DAYS` | No | `30` | Auth token lifetime in days (`0` = never expires) |
| `ADMIN_URL` | No | `admin/` | Admin path (change it to obscure `/admin/`) |
| `SITE_URL` | No | `http://localhost:8000` | Public base URL (payment webhooks) |
| `CHAPA_SECRET_KEY` | No | — | Chapa payment secret |
| `CHAPA_WEBHOOK_SECRET` | No | — | Chapa webhook HMAC secret |
| `FCM_SERVER_KEY` | No | — | FCM server key (push) |
| `REMINDER_SECRET` | No | — | Secret for the reminders task endpoint |
| `SMS_API_KEY` / `SMS_PROVIDER_URL` | No | — | SMS provider (OTP + password reset) |

### Flutter App
```bash
cd lets_play_app
flutter run -d <device-id>
# Or build + install without re-login:
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

---

## Key Data Models

| Model | Purpose |
|-------|---------|
| `User` / `UserProfile` | Auth, profile, location, bio, favorite sports |
| `Match` | Match event with sport, time, location, price |
| `MatchParticipant` | User + match join, with `team_group` (A/B) |
| `MatchResult` | Outcome, winner, score, MVP |
| `Team` | Team with owner, sport, location |
| `TeamMember` | User membership in a team |
| `League` | Competition with format, max teams, prize |
| `LeagueMember` | Team in a league, with standings stats |
| `UserSportRating` | Per-user per-sport Glicko-2 rating (rating, RD, volatility) |
| `TeamRanking` | Per-team per-sport league ranking |
| `ChatMessage` | Message for a match or team chat |
| `Notification` | In-app notifications |
| `RecommendationExposure` | A ranked match that was shown to a user |
| `ModelArtifact` | Trained model weights + readiness metadata |
| `NotificationBandit` | Thompson-sampling posterior per notification arm |
| `HostAccount` | Payee available/pending/paid-out balances |
| `HostLedgerEntry` | Signed payee ledger (match/venue releases, payouts, clawbacks) |
| `HostPayout` | Withdrawal request with status + transfer reference |
| `MatchPot` | Collected pot, venue payment, service fee, held surplus |
| `MatchWithdrawal` | Post-booking withdrawal + funded replacement slot |
| `PlayerCreditAccount` / `PlayerCreditEntry` | In-app credit from match surplus |

---

## Test User

- **Name**: Naod Masresha
- **Email**: naodog00@gmail.com
- **Phone**: +251947892090

---

## Growth & Retention Algorithms

> **Status: built.** The rules layer, exposure logging, experiments, reliability,
> collaborative filtering, Glicko-2, notification bandits and the post-match loop
> are live. The learned join/churn/fill models are implemented and activate
> automatically once their data thresholds are met; until then every caller uses
> the rules fallback. `python manage.py train_models` reports current readiness.

### Context: what already exists

The product combines a rules-based retention engine with a full analytics
pipeline. The algorithms below are an upgrade path, not a greenfield build.

**Base layer (live)**
- Personalized match ranking: sport affinity, city/location, urgency, scarcity,
  premium organizer, collaborative filtering, organizer reliability.
- Next-best-action per user: match soon, fill match, premium expiry, streak risk,
  win-back, discover, host fallback.
- Weekly activity streaks and a rules-based at-risk score.
- Automated nudges (`run_engagement_jobs`): fixture reminders, fill assistant,
  win-back, premium expiry, streak nudges, post-match rematch, weekly recap
  (all deduplicated, frequency-capped, and send-time aware).
- Analytics: event ingestion, funnels, retention cohorts, screen time, feature
  adoption, business metrics, and the staff dashboard at `/insights/`.
- Elo ratings, team standings, and match results as the foundation for Glicko-2.

**New in this layer (built)**
- Recommendation exposure logging and deterministic A/B experiments.
- Reliability scoring, co-participation collaborative filtering, ranking v2 with
  human-readable reasons and online exploration.
- Join-propensity, churn, and fill-probability models (pure-Python logistic
  regression; weights in the database; rules fallback).
- Notification bandits (Thompson sampling), send-time windows, quiet hours, and
  frequency caps.
- Glicko-2 ratings with rating deviation + volatility.
- Post-match rematch loop and weekly recap.

---

### What TikTok, Instagram and Tinder actually use

| Mechanic | TikTok | Instagram | Tinder | Rivalink translation |
|---|---|---|---|---|
| Two-stage recommender | Candidate generation, then rank by predicted watch time / completion / share | Candidate generation, then rank by predicted like/comment/save/time | Rank people by desirability, activity, recency, distance | Rank **matches/opponents**, never people's worth |
| Fast feedback loop | Every view/rewatch/scroll is a label | Every engagement trains the feed | Swipe is a perfect label | `viewed -> join tap -> joined -> completed -> rated -> returned` |
| Variable reward | "Next video might be great" | Likes and social validation | Match + scarcity/near-miss | Close matches, Elo movement, rank tiers, streaks, rivalries |
| Habit scaffolding | Notifications, infinite scroll | Notifications, Stories, streaks | Activity nudges, boosts | Real games with real people expecting you, timed reminders |

The goal for a sports utility is **not** time-in-app. It is **completed matches
per week** and repeat participation. Optimize the outcome, not the scroll.

---

### Phase A — Instrumentation and rules (live)

**A1. Exposure logging + experiments**
- Model `RecommendationExposure`: user, match, surface, variant, score, features
  (JSON at serve time), created_at.
- Every recommended match served logs an exposure, so models learn from what was
  shown, not just what was joined.
- Deterministic A/B assignment: `sha256(experiment + user_id)` mapped to variants
  (`A` control, `B` treatment) — no database needed for assignment.
- Experiments: ranking weights and notification copy.

**A2. Reliability score** (`core/reliability.py`)
- Inputs: no-shows, host cancellations, received ratings.
- Formula: `100 - 15*no_shows - 10*host_cancellations + 10*(avg_rating-3)`,
  clamped to 0–100. Default 100 for new users.
- Used in ranking, fill notifications, and exposed in `/api/engagement/status/`.

**A3. Ranking v2** (`core/engagement.py`)
- Base score: `0.40* sport fit + 0.20* location + 0.15* urgency + 0.10* scarcity
  + 0.10* CF + 0.05* organizer quality`, normalized to 0–100.
- Every recommendation carries human-readable **reasons**: "Your sport",
  "Near you", "Starts soon", "Only 3 spots left", "Reliable organizer",
  "Players like you joined".
- **Exploration:** 10–18% of slots go to new/uncertain matches (appended below
  top picks) so the feed does not collapse into one sport/location.
- Join-propensity probability is blended in when its model is ready.
- The app renders the top reason on recommendation cards.

**A4. Collaborative filtering** (`core/collaborative.py`)
- Co-participation: users who joined match A also joined match B.
- Item-item scores computed on the fly; cold start returns nothing until a user
  has at least 3 participations.

**A5. Post-match rematch loop**
- 24–48h after a confirmed result, participants get one deduplicated nudge with
  the next recommended match (or a rematch prompt).
- Goal: turn one match into the next without the user browsing.

**A6. Weekly recap + frequency caps**
- Monday recap: matches played last week, streak, upcoming fixture, next match.
- Hard caps: max 2 notifications/day and 6/week per user; transactional
  messages (match today, fixture reminder) can bypass the cap.
- Quiet hours 22:00–07:00 and per-user activity windows gate generic nudges.

---

### Phase B — Learned models (live code, activate at data thresholds)

**B1. Join-propensity model**
- **Label:** did the user join the exposed match within 24h?
- **Features:** sport affinity, distance/city, price, hours to start, spots left,
  day/time, skill level, organizer reliability, user's historical join rate for
  the sport, CF score, premium organizer, prior exposure count.
- **Training:** pure-Python logistic regression (no external ML dependency),
  batch gradient descent with L2; features standardized and stored with weights
  in `ModelArtifact`.
- **Inference:** blend 60% rules + 40% model probability; fall back to rules if
  no artifact is ready.
- **Unlock threshold:** ≥200 exposures older than 24h and ≥30 positive joins.
- **Implemented in:** `core/ml.py`; `GET /api/matches/recommendations/` returns
  `reason`, `reasons`, `recommendation_variant`, and `join_probability` once
  available.

**B2. Churn model**
- **Dataset:** rolling 6-week window. Features from days 1–28: days since last
  event, sessions in 7/28 days, matches joined/hosted in 28 days, streak,
  no-shows, premium status, reliability. Label: any activity in days 29–42.
- **Use:** blends with the rules at-risk score; win-back only targets users whose
  blended risk is meaningful.
- **Unlock threshold:** ≥300 labeled users; retrain weekly, rules stay as
  fallback.

**B3. Fill-probability model**
- **Dataset:** closed matches older than 1 hour.
- **Features:** sport, capacity, price, lead time (created→kickoff), day/time,
  city-independent organizer reliability. Live fill progress is blended at
  inference, so training does not leak final fill counts.
- **Use:** fill assistant prioritizes matches least likely to fill; the host
  next-best-action and match ranking can surface the estimate.
- **Unlock threshold:** ≥50 closed matches.

**B4. Notification bandits**
- Arms: send-time windows (morning/afternoon/evening) and copy variants (A/B).
- Thompson sampling with Beta(alpha, beta) per user/arm in `NotificationBandit`.
- Reward: user active within 24h after a notification (from analytics events).
- A `notification_sent` analytics event records the arm for later reward updates.
- Frequency caps and quiet hours override the bandit.

**B5. Glicko-2 ratings**
- Replaces K-factor Elo and tracks rating uncertainty.
- `UserSportRating` now stores `rating_deviation` (default 350) and `volatility`
  (default 0.06); one match is one rating period.
- Team games update each player against the opposing group's players with
  win/loss/draw scores (one period, multiple opponents).
- Rating deviation is available for future matchmaking and is updated on every
  confirmed result.

---

### Phase C — Scale (after retention and revenue are proven)

- Two-tower retrieval/embeddings for match and player recommendations.
- Session-sequence model for "what does this user want right now".
- Sponsor-audience matching from analytics segments.
- LTV/CAC cohort modeling and pricing experiments (A/B, not manual guesses).
- Dynamic featured listings, with clear labeling and no pay-to-win ranking.

---

### Modules, endpoints and commands

| Item | Purpose |
|---|---|
| `core/reliability.py` | Reliability scoring |
| `core/experiments.py` | Deterministic A/B assignment |
| `core/collaborative.py` | Co-participation item-item scores |
| `core/ml.py` | Logistic regression, feature builders, artifacts |
| `core/glicko2.py` | Glicko-2 rating updates |
| `core/bandit.py` | Thompson sampling, send windows, frequency caps |
| `RecommendationExposure` model | Serve-time impression logging |
| `ModelArtifact` model | Trained weights, metadata, sample counts |
| `NotificationBandit` model | Per-user/arm Beta parameters |
| `GET /api/engagement/status/` | Includes reliability, model status, experiments |
| `GET /api/matches/recommendations/` | Includes reasons, variant, join probability |
| `python manage.py train_models` | Train join/churn/fill models when thresholds are met |
| `python manage.py update_bandits` | Reward notification bandits from 24h activity |
| `python manage.py run_engagement_jobs` | Rematch + weekly recap + fill probability + caps |

Run the model/bandit jobs weekly (they are safe to run daily; they only report
"waiting" below threshold):

```bash
cd backend
./venv/Scripts/python manage.py train_models
./venv/Scripts/python manage.py update_bandits
```

`train_models` prints samples/positives versus each threshold. The app never
requires an artifact to work — the rules layer is the permanent fallback.


---

### Metrics that decide whether this works

**North star:** completed matches per week.

**Diagnostics:** request→completion rate, D7/D30 retention, match fill rate,
no-show rate, time-to-match, sessions per week, premium conversion, net revenue,
refund rate, contribution margin.

**Guardrails:** notification unsubscribes, notification-to-open rate, users
blocking the app, cancellations after notifications, complaints.

If time-in-app rises while completed matches fall, the algorithms are optimizing
the wrong thing.

---

### Data timeline

| Week | What happens |
|---|---|
| 0–2 | Exposure logging, experiments, reliability, ranking v2, CF, rematch loop — **done** |
| 2–6 | Collect labels (exposures → joins, results, notifications → activity) |
| ~6 | `train_models` reports readiness; join/churn/fill models activate |
| 6+ | Weekly retraining, bandit optimization, Glicko-2 in matchmaking |
| 12+ | Scale-phase ideas only if retention and revenue hold |

`train_models` prints readiness (samples / positives / threshold) and skips
training below thresholds. Every model has a rules-based fallback.

---

### Ethical guardrails (non-negotiable)

- **Rank matches and opportunities, not people's worth.** No desirability scores
  on users.
- **No gambling-style mechanics.** No paid prize pools framed as betting, no
  loot-box behavior.
- **No fake urgency or fake scarcity.** Every "3 spots left" must be real.
- **No pay-to-be-seen beyond clearly labeled featured listings.** Reliability and
  relevance determine ranking.
- **Notification discipline.** Hard frequency caps, quiet hours, and no promos
  when a user already has a match.
- **Transparency.** Users can see why a match was recommended and can opt out of
  analytics/personalization in Settings.
- **Privacy.** Models use aggregated/behavioral data, never message contents or
  personal contact details. No PII in events.
- **Streak grace.** One missed week should not wipe months of progress; allow a
  grace period or a streak freeze earned through participation.

