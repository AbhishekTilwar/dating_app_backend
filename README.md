# Spark — Meaningful connections, designed for real life

A modern dating app built with **Flutter** (Material 3) and **Firebase** (Auth, Firestore, Storage), with a **Node.js** backend. The design takes the best from Bumble and Hinge and addresses common dating-app pain points: safety, transparency, and conversation quality.

---

## What makes Spark different

- **Designed to be deleted** — Focus on real connections, not endless scrolling (e.g. daily suggestion limits).
- **You’re in control** — Relationship goals, dealbreakers, and optional “who makes the first move” (Bumble-style).
- **Safe and transparent** — Report and block in 2–3 taps; verified profiles; clear community guidelines.
- **Conversations that start well** — Prompts and “opening moves” (Bumble-style) so chats have a clear starting point.
- **Light, friendly UI** — Material 3, light theme, clean layout, smooth transitions and scroll-triggered motion.

---

## Project structure

```
DatingApp/
├── app/                 # Flutter app (Spark)
│   ├── lib/
│   │   ├── core/        # Theme, router, constants, services
│   │   ├── features/   # Auth, onboarding, profile, discovery, matches, chat
│   │   └── shared/     # Reusable widgets (e.g. parallax)
│   └── pubspec.yaml
├── backend/             # Node.js API
│   ├── src/
│   │   └── index.js    # Express + Firestore + Auth + Storage
│   ├── package.json
│   └── .env.example
└── README.md
```

---

## Features implemented

| Feature | Flutter | Backend |
|--------|--------|--------|
| Firebase Auth (phone + Google) | ✅ Sign in & sign up same flow, AuthService | ✅ `requireAuth` verifies ID token |
| Onboarding | ✅ 4-step light copy | — |
| Profile setup | ✅ Firestore + Storage, live stream on Profile tab | ✅ PUT /api/users/me, `profileComplete` |
| Auth → home flow | ✅ Splash routes by `profileComplete` | ✅ Discovery only `profileComplete` users |
| Discovery | ✅ Card stack, like/pass/super like, prompts on cards | ✅ GET /api/discovery, likes/passes |
| Matches & chat | ✅ List, chat UI, report/block in 2 taps | ✅ Matches, messages, reports, blocks |
| Safety | ✅ Report reasons, block dialog, Safety in nav | ✅ /api/reports, /api/blocks |
| Material 3 light theme | ✅ AppTheme.light, DM Sans | — |
| Animations | ✅ Splash, onboarding, list stagger, discovery scale | — |
| Parallax / scroll | ✅ ParallaxSection widget, scroll-based reveal | — |

---

## Setup & Running

See `app/README.md` and `backend/README.md` for specific instructions.

---

## License

Private / educational use.
