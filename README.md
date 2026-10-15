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
   - Match recommendations ("Recommended For You" by favorite sports)
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
   - **Individual Elo ratings** per sport (initial 1200, K=32/48 based on experience)
   - **Team ranking** with points-based league standings
   - Rankings screen with tab toggle (Individual / Teams) and sport filter
   - User profile shows per-sport Elo with W/L/D

6. **Match Results & Scorekeeping**
   - Record match outcomes (pickup, 1v1, team vs team)
   - MVP selection for pickup matches
   - **Team group assignments** (A/B) for team sports with individual Elo
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

### 💎 Premium (~50-100 ETB/mo)
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
- **Premium subscription system** (payment integration, dynamic checks, upsell UI)

### 🟡 Medium Priority
- **Dispute resolution** (conflict process, refunds)
- **Advertising system** (banners, sponsored content)
- **Venue owner dashboard** (manage listings, view booking stats)

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
- **Decimals**: Range-bounded (entry_fee: 0-999999, price_per_hour: 0-999999)
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

### Flutter App
```bash
cd Rivalink
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
| `UserSportRating` | Per-user per-sport Elo rating |
| `TeamRanking` | Per-team per-sport league ranking |
| `ChatMessage` | Message for a match or team chat |
| `Notification` | In-app notifications |

---

## Test User

- **Name**: Naod Masresha
- **Email**: naodog00@gmail.com
- **Phone**: +251947892090
