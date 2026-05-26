# Grye Premium Fintech Neo-Banking Mobile Application

An ultra-premium, dark-luxury fintech mobile application inspired by Grey, Revolut, Wise, and modern neo-banking platforms. Designed for institutional-grade cross-border wealth management, virtual card issuing, real-time exchange networks, and biometric compliance.

---

## 💎 Tech Stack & Architecture

- **Mobile Framework**: React Native Expo (SDK 51) with TypeScript and cross-platform Web/Mobile support
- **State Management**: Zustand high-speed store with Firestore ledger syncing
- **Database / Backend**: Firebase Suite
  - **Firebase Authentication**: Persistent JWT-session email/password, biometric, and phone OTP verification
  - **Cloud Firestore**: Highly optimized real-time ledger data streams
  - **Firebase Storage**: Compliance KYC upload pipelines with strict security rules
- **Styling & Design System**: Dark luxury obsidian palette, glassmorphism containers, custom glowing nodes, and neon green accents (`#00FF66`)
- **Graphics**: Curved charts designed with vector SVGs for fluid 60FPS visual rendering
- **Continuous Integration**: GitHub Actions CI/CD pipeline checking types and dry-run web builds automatically on pull requests

---

## 📂 Core Folder Structure

```text
grye-fintech/
├── .github/
│   └── workflows/
│       └── ci.yml             # CI/CD type-checking & dry-run compilation
├── assets/                    # Platform icons & launch screens
├── src/
│   ├── components/            # High-fidelity reusable UI components
│   │   ├── GlassCard.tsx      # Core luxury glassmorphic wrapper
│   │   ├── PremiumVisaCard.tsx# Interactive credit card (freeze/unfreeze, CVV hide/show)
│   │   └── TransactionList.tsx# Statistical debit/credit ledger row feed
│   ├── screens/               # Comprehensive feature screens
│   │   ├── OnboardingScreen.tsx # Cinematic multi-step storytelling
│   │   ├── AuthScreen.tsx       # Email, phone OTP, and biometric simulators
│   │   ├── DashboardScreen.tsx  # Total balance aggregates & real-time converter
│   │   ├── VirtualCardScreen.tsx# Visual Visa cards dashboard with spending sliders
│   │   ├── TransferScreen.tsx   # Global wire transfers with receipts
│   │   ├── ReceiveScreen.tsx    # USD/EUR/GBP account credentials & QR codes
│   │   ├── AnalyticsScreen.tsx  # curved SVG charts and category spending progress
│   │   ├── KYCScreen.tsx        # Compliance document cameras & OCR match matrices
│   │   └── SettingsScreen.tsx   # Themes, languages, and session logs
│   ├── services/
│   │   └── firebase.ts        # persistent local caching client setup
│   ├── store/
│   │   └── useAppStore.ts     # Master Zustand state machine
│   └── theme/
│       └── colors.ts          # Caviar, Platinum, and Obsidian design tokens
├── App.tsx                    # Shell layout switcher & web frame emulator wrapper
├── firestore.rules            # Immutable transaction rules & security logic
├── storage.rules              # KYC document restrictions and size caps
├── package.json               # Core dependencies
└── tsconfig.json              # Strict TypeScript audit configurations
```

---

## 🔒 Firebase Database & Security Rules

### Optimized Database Collections Schema

1. **`users/{userId}`**: Profiles, telephone credentials, membership statuses, and biometric signatures.
2. **`wallets/{walletId}`**: Account balances, Swift/BIC credentials, routing indices, and IBAN logs.
3. **`cards/{cardId}`**: Spend locks, monthly thresholds, color themes, card details, and frozen states.
4. **`transactions/{transactionId}`**: Ledger logs detailing sender indices, recipient IDs, raw amounts, and execution dates.
5. **`kyc/{kycId}`**: Upload statuses, image URLs, matching accuracy matrices, and audit dates.
6. **`notifications/{notificationId}`**: Targeted transaction alerts and push updates.
7. **`exchangeRates/{rateId}`**: Global conversion rates read by users.

### Security Rules Highlights (`firestore.rules` & `storage.rules`)

- **Profile Isolation**: Users can only read and write their own documents matching their authenticated UID.
- **Immutable Transactions**: Transactions can only be created by the verified sender. Updates and deletions are completely blocked to guarantee ledger audits.
- **Role-Based Control**: Global exchange indices can only be modified by secure admin server systems, but read by all authenticated clients.
- **KYC Isolation & Upload Constraints**: KYC storage folders are private to the user UID. Files uploaded are limited to a strict size ceiling of `10MB` to prevent malicious server floods.

---

## ⚙️ Installation & Setup Guide

### Prerequisites
- Node.js (version 18 or higher recommended)
- Git CLI
- Expo Go on iOS/Android (for physical device testing)

### 🚀 Get Up and Running Instantly

1. **Clone and Navigate**:
   ```bash
   git clone https://github.com/lhossohmida-lang/sssss.git
   cd grye-fintech
   ```

2. **Install Dependencies**:
   ```bash
   npm install
   ```

3. **Configure Environments**:
   Create a `.env` file in the root directory using the template inside `.env` or paste the credentials provided in the configuration block.

4. **Launch the Development Server**:
   - For **Mobile Simulation** (Android/iOS):
     ```bash
     npm run start
     ```
   - For **Instant Web Preview / Browser Testing**:
     ```bash
     npm run web
     ```

---

## 🧪 CI/CD Operations & Type Checking
To run continuous integration checks locally:
```bash
npm run ts:check
```
Every pull request triggers the CI pipeline inside `.github/workflows/ci.yml` verifying TypeScript compilations, dependency health checks, and static asset evaluations to ensure a zero-defect main branch.

---

*Grye Elite Club Neo-Banking is an intellectual conceptual platform designed in compliance with modern banking regulations.*
