# Product Requirements Document (PRD)

| | |
| --- | --- |
| **Project Name** | Kushol (কুশল) |
| **Tagline** | The Educational Super App for Communities, Commerce, and AI-Driven Growth. |
| **Platforms** | Mobile App (iOS via TestFlight, Android via Expo CLI) & Web (Landing Page + Admin Dashboard) |
| **AI Infrastructure** | DeepSeek (via CommandCLI) |
| **Document Status** | VC Pitch Ready & Developer Handoff |

---

## 1. Executive Summary

Kushol is a zero-CAC (Customer Acquisition Cost) B2B2C educational super app tailored for
Bangladesh. By onboarding a single school, the platform instantly acquires thousands of captive
users (students, teachers, and guardians). It replaces chaotic WhatsApp groups with a strict,
hierarchy-driven messaging platform, and scales revenue through integrated fee payments, campus
commerce, peer-to-peer tuition matchmaking, and DeepSeek-powered AI study tools.

## 2. Target Audience

- **Students (B2C):** Need organized study materials, AI test prep, and senior tutors.
- **Guardians (B2C):** Need direct school updates, easy fee payment, and verified tutors.
- **Schools/Colleges (B2B):** Need streamlined communication, automated fee collection, and LMS
  integration.
- **Vendors/Brands (B2B):** Need hyper-targeted access to student demographics for commerce and
  ads.

## 3. Product Phasing Strategy

### Phase 1: The MVP (Community & Communication)

- **Mobile App Release:** Built on React Native (Expo CLI). Android APK release and iOS Beta via
  TestFlight.
- **Web Dashboard:** Landing page for B2B lead generation (schools) and Super Admin portal.
- **Features:** Hierarchical group creation (City → School → Section), Student Ambassador
  verification, Role-based messaging (PDF, Images, Voice), and one-way Notice Boards.

### Phase 2: The Marketplace & FinTech Expansion

- **Features:** bKash/Nagad/SSLCommerz integration for fee payments with automated reconciliation.
- **Campus Commerce:** Local vendors and schools setting up storefronts for books and uniforms.
- **Basic Migration:** CSV/Excel upload for year-end student migration.

### Phase 3: The AI & Ecosystem Scale

- **Features:** DeepSeek integration for Smart Study Hub (Notes scanning, Auto-CT generation).
- **Tuition Marketplace:** Location and skill-based matching for home tutors.
- **Advanced Migration:** REST API Webhooks for live LMS/ERP syncing.

## 4. Platform Interfaces

### A. The Landing Page & Web Admin Dashboard

The web portal serves two distinct purposes:

- **Public Landing Page:** A B2B marketing funnel designed to convert School Principals and
  Vendors. Features ROI calculators for schools (time saved on fee collection) and registration
  forms.
- **Command Center (Dashboard):**
  - **Super Admin:** Manages tenant schools, approves vendors, and monitors platform revenue.
  - **School Admin:** Uploads CSV rosters, triggers fee payment links, sends global notices, and
    views the AI Teacher Assistant Pain Point Matrix.
  - **Vendor Portal:** Inventory management, order fulfillment tracking, and targeted ad campaign
    creation.

### B. Mobile App (Student, Teacher, Guardian)

Built using Expo CLI for rapid cross-platform deployment.

- **iOS Distribution:** Internal testing and early school rollouts managed via Apple TestFlight.
- **Android Distribution:** Direct APK downloads for immediate onboarding, followed by Play Store
  release.

**Core UI Tabs:**

| Tab | Contents |
| --- | --- |
| **Chat** | Segmented into Official (Class/Section), Custom (Clubs), and DMs. |
| **Notices & Events** | School broadcasts and city-wide educational campaigns. |
| **AI Hub** | Note scanner, MCQ generator, and study materials. |
| **Marketplace** | Pay fees, buy books, or find a home tutor. |

## 5. Core Feature Specifications

### 5.1 Communication Engine & Hierarchy

- **Strict Onboarding:** Users select City → Institution → Section. Status remains "Pending" until
  verified by an Admin or Student Ambassador.
- **Auto-Grouping:** Verified students are automatically placed in their Class group (managed by
  the Class Teacher) and the School Notice Board.
- **Multi-Tenant Privacy:** Data is completely isolated per institution. Inter-school DMs require
  a "Message Request" acceptance to prevent spam.

### 5.2 DeepSeek AI Integration

- **Smart Study Hub:** Students snap photos of notes/exams. DeepSeek's vision model tags and
  archives them into a searchable school-wide database.
- **Auto-CT (Class Test):** Teachers prompt the AI to generate MCQs based on specific chapters.
  The app administers and auto-grades the test.
- **Pain Point Matrix:** DeepSeek analyzes failed MCQ topics and chat queries, providing teachers
  a weekly dashboard report (e.g., "60% of Section B is struggling with Calculus limits").

### 5.3 Peer-to-Peer Tuition Marketplace

- **Post Requirements:** Guardians/Students post requirements (Subject, Budget, Location).
- **Smart Matching:** The system notifies verified university/senior students within the exact
  geo-radius whose profiles match the subject expertise.

### 5.4 Smart Payments & E-Commerce

- **Fee Collection:** Push notifications with deep links to payment gateways. Successful payments
  auto-generate PDF receipts and update the School Admin's dashboard ledger.
- **Campus Commerce:** Local stores list uniforms/books with options for in-store pickup or local
  courier delivery.

## 6. Technical Stack

| Layer | Technology |
| --- | --- |
| Frontend Mobile | React Native (Expo CLI) |
| Frontend Web/Dashboard | Next.js, Tailwind CSS |
| Backend & APIs | GoLang (chi REST + gorilla/websocket for high-concurrency messaging); AI service later extracted to Python FastAPI |
| Database | PostgreSQL (Multi-tenant architecture) + Redis (for real-time chat caching) |
| Real-time Engine | WebSockets & Firebase Cloud Messaging (FCM) via Topic Subscriptions |
| AI Infrastructure | DeepSeek V4 Flash API (via commandcli) for low-latency, low-cost NLP and vision tasks |

## 7. Revenue Model (VC Pitch)

Kushol utilizes a highly scalable B2B2C monetization matrix:

### 1. FinTech Convenience Fees (High Volume)

- **Mechanism:** BDT 15–20 flat fee charged to guardians for every school fee/tuition transaction
  processed in-app.
- **Scale:** 100 schools × 2,000 students × 12 months = 2.4 million transactions annually.

### 2. Marketplace & Tuition Commissions (High Margin)

- **Tuition Matchmaking:** 50% cut of the tutor's first month salary as a successful
  matchmaking/lead fee, or a BDT 300/month premium tutor subscription.
- **Campus Commerce:** 5% to 10% commission on vendor sales (books, uniforms, stationeries)
  processed through the Kushol marketplace.

### 3. Hyper-Targeted B2B Ads & Lead Gen

- **Mechanism:** EdTech brands (e.g., admission coachings) pay for sponsored push notifications or
  native ads targeting specific demographics (e.g., "Class 12 Science students in Dhaka").
- **Event Ticketing:** 10% commission on tickets sold for city-wide educational campaigns hosted
  on the platform.

### 4. B2B SaaS & Premium Consumer AI (Recurring)

- **B2B SaaS:** The basic app is free. Schools pay an annual licensing fee to unlock the ERP/LMS
  Sync, Automated Fee ledgers, and the AI Pain Point Matrix.
- **B2C Freemium:** Students receive 5 free AI-generated MCQs weekly. A "Kushol Pro" subscription
  (BDT 99/month) unlocks unlimited AI tests and advanced AI study notes.
