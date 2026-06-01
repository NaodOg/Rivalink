# PlayFair - Sports Matchmaking App

## Overview

PlayFair is a full-stack sports platform built with Flutter (mobile app) and Django REST API (backend). The app enables users to organize and join matches, create and manage teams, participate in leagues, and connect with other players.

---

## Business Model Analysis

### Revenue Streams - Current Implementation Status

| Revenue Stream | Status | Notes |
|---------------|--------|-------|
| Commission Per Match | ⚠️ Partial | Match creation exists, but no payment processing |
| Premium Subscription | ❌ Not Implemented | No subscription system |
| Tournament Hosting Fees | ⚠️ Basic | League system exists, but no bracket/payment |
| Venue Booking Partnerships | ❌ Not Implemented | No venue management |
| Sponsorships/Advertising | ❌ Not Implemented | No ad system |
| Verified Referee Marketplace | ❌ Not Implemented | No referee system |
| Corporate/Sponsored Matches | ❌ Not Implemented | No event management |
| Data & Analytics | ⚠️ Basic | User stats exist, not monetized |

---

## What's Already Implemented

### ✅ Core Features

1. **User Authentication**
   - Sign up / Login with email and phone
   - Session management
   - Profile editing

2. **Match System**
   - Create matches (sport, date, time, location, price, max players)
   - Join/Leave matches
   - Match details view
   - Match chat
   - Match history
   - Search and filter matches

3. **Team Management**
   - Create teams
   - Join/Leave teams
   - Team members management
   - Team owner controls
   - Team recruitment (seeking players)

4. **League System**
   - Browse leagues
   - Join leagues
   - League details

5. **Social Features**
   - In-app notifications (bell icon)
   - Direct messaging (backend ready, UI pending)

6. **Player Ratings**
   - Rate players after matches (1-5 stars + comments)
   - View user ratings

7. **Match Results**
   - Record match outcomes
   - Match types: Pickup Game, Team vs Team, Individual
   - MVP selection for pickup matches

8. **User Profile & Stats**
   - Profile editing with photo
   - Stats: matches played, wins, losses, teams owned, teams joined, average rating

9. **Favorites**
   - Favorite teams
   - View favorited teams

10. **Match Recommendations**
    - "Recommended For You" section based on favorite sports

---

## Premium Subscription System

### Free vs Premium Feature Split

#### 🆓 Free Version
| Feature | Limit |
|---------|-------|
| Create matches | 3 per month |
| Join matches | Unlimited |
| Create teams | 1 team |
| Join teams | 3 teams max |
| Match recommendations | Basic (favorites only) |
| Team analytics | Basic stats |
| Direct messaging | Only with matches |
| Profile visibility | Standard |
| Ad-supported | Yes |

#### 💎 Premium ($5/month)
| Feature | Benefit |
|---------|---------|
| **Unlimited matches** | No limits on creating |
| **Unlimited teams** | Join/create as many as you want |
| **Advanced matchmaking** | AI matching by skill level, availability |
| **Tournament access** | Join paid tournaments |
| **Priority booking** | Appear first in search results |
| **Premium badge** | Gold icon on profile |
| **Team analytics** | Advanced stats, win trends |
| **Unlimited messaging** | Message any player |
| **VIP support** | Faster response |
| **Ad-free** | No sponsored content |

### Subscription Tiers

| Tier | Price | Features |
|------|-------|----------|
| **Free** | $0 | Basic matching, 3 matches/mo, 3 teams |
| **Premium** | $5/mo | Unlimited everything, tournaments, priority |
| **Pro** | $15/mo | + Team analytics, API access, dedicated support |

### Technical Implementation Required

**1. Backend - User Model Addition**
```python
# core/models.py - Add to UserProfile
is_premium = models.BooleanField(default=False)
premium_expires = models.DateTimeField(null=True)
subscription_tier = models.CharField(max_length=20, choices=[
    ('free', 'Free'),
    ('premium', 'Premium'),
    ('pro', 'Pro'),
], default='free')
```

**2. Backend - Permission Checks**
```python
# core/views.py - Check limits
def can_create_match(user):
    if user.profile.subscription_tier != 'free':
        return True
    this_month = timezone.now().replace(day=1)
    count = Match.objects.filter(organizer=user, created_at__gte=this_month).count()
    return count < 3
```

**3. Flutter - Entitlement Service**
```dart
// lib/services/premium_service.dart
class PremiumService {
  static bool get isPremium => 
    userData['subscription_tier'] != 'free';
  
  static bool get canCreateUnlimitedMatches => isPremium;
  static bool get canJoinUnlimitedTeams => isPremium;
  static bool get hasPriorityVisibility => isPremium;
}
```

### Payment Integration Required

- **Store**: Flutter In-App Purchases (iOS) / Google Play Billing (Android)
- **Provider**: 
  - Stripe (international payments)
  - Flutterwave (Ethiopia/Africa - supports mobile money)
- **Verification**: Server-side receipt validation

### Revenue Projection

| Metric | Free Tier | Premium Tier |
|--------|-----------|--------------|
| Users | 5,000 | 200 (4% conversion) |
| Price | $0 | $5/month |
| Revenue | $0 | $1,000/month |

---

## What's Missing (Business Model Gap)

### 🔴 High Priority

1. **Payment Processing**
   - No payment integration (Stripe, Flutterwave, etc.)
   - No escrow system for match funds
   - No split payments (venue, referee, platform)

2. **Premium Subscription System**
   - No subscription tiers
   - No entitlement system (free vs premium features)
   - No in-app purchase integration

3. **Referee System**
   - No referee profiles
   - No referee booking
   - No referee verification

4. **Venue Management**
   - No venue owner accounts
   - No venue listing/booking
   - No availability calendar
   - No venue verification

### 🟡 Medium Priority

5. **Tournament System**
   - Basic leagues exist, but no brackets
   - No tournament entry fees
   - No prize pool management
   - No elimination brackets

6. **Dispute Resolution**
   - No conflict resolution process
   - No refund policy enforcement
   - No arbitration system

7. **Rating & Review System**
   - Player ratings exist
   - No venue ratings
   - No referee ratings
   - No team ratings

8. **Corporate/Event Management**
   - No event creation for companies
   - No charity match handling
   - No event scheduling tools

### 🟢 Low Priority

9. **Advertising System**
   - No ad banners
   - No sponsored content
   - No promoted matches

10. **Insurance/Liability**
    - No terms of service
    - No liability waivers
    - No injury reporting

11. **Data & Analytics Monetization**
    - Basic stats exist
    - No premium analytics
    - No data export for clubs/academies

---

## Recommended Priority for MVP

### Phase 1: Core Revenue (Now)
1. Match commission system with payment processing
2. Basic subscription tiers (Free vs Premium)

### Phase 2: Growth (Soon)
3. Tournament/league fees
4. Player/venue/referee ratings

### Phase 3: Scale (Later)
5. Venue partnerships
6. Corporate events
7. Advertising
8. Data analytics products

---

## Technical Stack

### Frontend (Flutter)
- **Framework**: Flutter 3.x
- **State Management**: setState (basic)
- **HTTP Client**: http package
- **Storage**: shared_preferences
- **UI**: Material Design 3, google_fonts, flutter_animate

### Backend (Django)
- **Framework**: Django 4.x + Django REST Framework
- **Authentication**: Token-based auth
- **Database**: SQLite (dev) / PostgreSQL (prod ready)
- **CORS**: django-cors-headers

### Infrastructure
- **Tunnel**: ngrok for development
- **API URL**: https://unpossessively-pseudonational-shawnta.ngrok-free.dev

---

## Project Structure

```
PlayFair/
├── backend/
│   ├── core/
│   │   ├── models.py       # All Django models
│   │   ├── views.py        # API endpoints
│   │   └── urls.py         # URL routing
│   ├── db.sqlite3          # Database
│   └── manage.py
├── lets_play_app/
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/         # Data models
│   │   ├── screens/       # UI screens
│   │   └── services/      # API services
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
```

### Flutter App
```bash
cd lets_play_app
flutter run -d <device_id>
# Device ID: RRCX202YH1P (Samsung SM-A256E)
```

---

## User Info

- **Test User**: Naod Masresha
- **Email**: naodog00@gmail.com
- **Phone**: +251947892090

---

## Future Considerations

### Payment Integration Options
- **Stripe** - International payments
- **Flutterwave** - Africa/Ethiopia focus
- **In-app purchases** - For subscriptions

### Key Metrics to Track
- Monthly Active Users (MAU)
- Matches created per month
- Conversion rate (free → premium)
- Average revenue per user (ARPU)
- Match completion rate

### Ethiopian Market Focus
- Football (soccer) is the dominant sport
- Basketball growing rapidly
- Volleyball popular
- Payment via mobile money (Ethio Telecom, Safaricom)
