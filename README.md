# PlayFair - Sports Matchmaking Platform

## Overview

PlayFair is a full-stack sports matchmaking platform built with **Flutter** (mobile app) and **Django REST Framework** (backend). Users can organize and join matches, create and manage teams, participate in leagues with Elo/points ranking, chat with teammates and match participants, and track their performance.

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

11. **Favorites**
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
            'error': 'All team members need PlayFair Premium to join a league'
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

### How PlayFair Makes Money from Brand Partnerships

Big brands (Fanta, Coca-Cola, Pepsi, banks, betting companies) have marketing budgets for community sports. They pay PlayFair to host branded leagues/tournaments — you get paid regardless of how many users are premium.

### Structure Options

#### 1. Flat Sponsorship Fee (Best for PlayFair)
Brand pays a flat fee to run the league under their name. Prize pool is separate.

| Item | Amount |
|------|--------|
| Brand pays PlayFair | **100,000 ETB** |
| Prize pool (brand-funded) | 50,000 ETB |
| PlayFair keeps | 100,000 ETB |
| 256 players wear branded jerseys for 8 weeks | — |

#### 2. Management Fee (20-30% cut)
| Item | Amount |
|------|--------|
| Brand total budget | 200,000 ETB |
| PlayFair management fee | **50,000 ETB** (25%) |
| Prize pool | 100,000 ETB |
| Operations (referees, venue, equipment) | 50,000 ETB |

#### 3. Entry Fee + Brand Top-Up (Recurring)
Teams pay entry, brand matches or tops up the prize pool.

| Item | Amount |
|------|--------|
| 32 teams × 1,000 ETB entry | 32,000 ETB |
| Brand prize top-up | 50,000 ETB |
| PlayFair takes 15% of entry fees | 4,800 ETB |
| Flat sponsorship fee | 30,000 ETB |
| **Total to PlayFair** | **~35,000 ETB per season** |

### Pitch Deck for Brands

```
PLAYFAIR x [BRAND] LEAGUE

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
- **Referee system** (profiles, booking, verification)
- **Venue management** (owner accounts, listing, booking calendar)

### 🟡 Medium Priority
- **Tournament system** (brackets, elimination, prize pools)
- **Dispute resolution** (conflict process, refunds)
- **Advertising system** (banners, sponsored content)

### 🟢 Low Priority
- **Corporate event management**
- **Insurance/liability** (ToS, waivers)
- **Data analytics monetization**

---

## Technical Stack

### Frontend (Flutter)
- **Framework**: Flutter 3.x
- **State Management**: setState + SessionController
- **HTTP Client**: `http` package
- **Storage**: `shared_preferences`
- **UI**: Material Design 3, `google_fonts`

### Backend (Django)
- **Framework**: Django 4.x + Django REST Framework
- **Authentication**: Token-based (DRF `Token` model)
- **Database**: SQLite (dev) / PostgreSQL (prod ready)
- **CORS**: `django-cors-headers`

### Infrastructure (Dev)
- **Tunnel**: ngrok for development
- **API URL**: `https://unpossessively-pseudonational-shawnta.ngrok-free.dev`

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
| **Domain** | e.g. `api.playfair.et` | ~$3/yr |
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
PlayFair/
├── backend/
│   ├── core/
│   │   ├── models.py          # Django models (User, Match, Team, League, etc.)
│   │   ├── views.py           # All API endpoints
│   │   ├── urls.py            # URL routing
│   │   ├── elo.py             # Elo calculation utility
│   │   └── migrations/        # DB migrations (0022 latest)
│   ├── letsplay_backend/
│   │   └── settings.py        # Django settings
│   ├── db.sqlite3             # SQLite database
│   └── manage.py
├── lets_play_app/
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/
│   │   │   ├── data/
│   │   │   │   ├── models/        # Dart data models
│   │   │   │   ├── repositories/  # AppRepository (service wrapper)
│   │   │   │   └── services/      # API service classes
│   │   │   ├── navigation/        # AppRoutes
│   │   │   ├── state/             # SessionController
│   │   │   ├── theme/             # PlayFairTheme
│   │   │   └── utils/             # Formatters
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
python manage.py runserver
# In separate terminal:
ngrok http 8000
# Update ngrok URL in service files if it changes
```

### Flutter App
```bash
cd lets_play_app
flutter run -d RRCX202YH1P
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
