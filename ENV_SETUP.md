# Environment Configuration Setup

## Overview
This project uses environment variables to securely manage Firebase credentials and other sensitive configuration. **Never commit actual credentials to version control.**

## Setup Instructions

### Step 1: Understand the Files

- **`.env.example`** - Template showing required environment variables (safe to commit ✓)
- **`.env`** - Your actual credentials (git-ignored, never committed ✗)
- **`lib/config/firebase_config.dart`** - Loads and validates environment variables

### Step 2: Create Your `.env` File

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Open `.env` and fill in your Firebase credentials:
   ```bash
   FIREBASE_API_KEY=your_actual_api_key
   FIREBASE_AUTH_DOMAIN=your-project.firebaseapp.com
   FIREBASE_PROJECT_ID=your-project-id
   # ... etc
   ```

### Step 3: Get Firebase Credentials

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Click **Project Settings** (gear icon)
4. Go to **General** tab
5. Find **"Your apps"** section → Web app
6. Copy the firebaseConfig values:
   ```javascript
   const firebaseConfig = {
     apiKey: "...",
     authDomain: "...",
     projectId: "...",
     // etc
   };
   ```

7. Map them to `.env`:
   - `apiKey` → `FIREBASE_API_KEY`
   - `authDomain` → `FIREBASE_AUTH_DOMAIN`
   - `projectId` → `FIREBASE_PROJECT_ID`
   - `storageBucket` → `FIREBASE_STORAGE_BUCKET`
   - `messagingSenderId` → `FIREBASE_MESSAGING_SENDER_ID`
   - `appId` → `FIREBASE_APP_ID`

### Step 4: Install Dependencies

```bash
flutter pub get
```

This will install `flutter_dotenv` which loads the `.env` file at runtime.

### Step 5: Run the App

```bash
flutter run
```

The app will automatically load configuration from `.env`.

## Environment Modes

The `.env` file supports multiple environments:

```bash
ENVIRONMENT=development    # For local development
ENVIRONMENT=staging        # For staging/testing
ENVIRONMENT=production     # For production
```

Check environment in code:
```dart
if (FirebaseConfig.isDevelopment()) {
  print('Running in development mode');
}
```

## For Different Team Members / Machines

Each developer should:
1. ✓ Commit: `.env.example` and code changes
2. ✗ Never commit: `.env` with their actual credentials
3. Each person runs: `cp .env.example .env` and fills in their own credentials

## For CI/CD Pipelines

When deploying via CI/CD:

1. **GitHub Actions** - Set secrets in your repo settings:
   ```yaml
   - name: Create .env file
     run: |
       echo "FIREBASE_API_KEY=${{ secrets.FIREBASE_API_KEY }}" >> .env
       echo "FIREBASE_PROJECT_ID=${{ secrets.FIREBASE_PROJECT_ID }}" >> .env
       # ... rest of secrets
   ```

2. **GitLab CI** - Set variables in project settings, then create `.env`:
   ```yaml
   script:
     - echo "FIREBASE_API_KEY=$FIREBASE_API_KEY" >> .env
     - flutter run
   ```

## Troubleshooting

### Error: "Missing required Firebase configuration"
- **Cause**: `.env` file is missing or empty
- **Solution**: Create `.env` from `.env.example` and fill in your credentials

### Error: "Could not initialize Flutter Dotenv"
- **Cause**: `.env` file not in project root
- **Solution**: Make sure `.env` is at the project root (same level as `pubspec.yaml`)

### Error: "flutter_dotenv not found"
- **Cause**: Dependencies not installed
- **Solution**: Run `flutter pub get`

### App won't start in web
- **Cause**: Invalid Firebase credentials
- **Solution**: Verify credentials in `.env` match Firebase Console exactly

## Security Best Practices

✅ **DO:**
- Store `.env` in your local machine only
- Rotate credentials regularly
- Use different credentials for dev/staging/prod
- Use secrets management in CI/CD
- Review `.gitignore` to ensure `.env` is excluded

❌ **DON'T:**
- Commit `.env` file to git
- Share `.env` file via email or chat
- Hard-code credentials in source code
- Use same credentials for dev and production
- Share API keys publicly

## Mobile Builds (Android/iOS)

For mobile, Firebase credentials are configured via:
- **Android**: `android/app/google-services.json` (git-ignored)
- **iOS**: `ios/Runner/GoogleService-Info.plist` (git-ignored)

These are handled separately from the `.env` file used for web builds.

## Questions?

See `COMPREHENSIVE_README.md` for full project documentation.
