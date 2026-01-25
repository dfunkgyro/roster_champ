# roster_champ

A new Flutter project.

## Build and Run (AWS)

Use `--dart-define` so public AWS config is injected at build/run time instead of bundled in assets.

Run (debug):

```bash
flutter run \
  --dart-define=AWS_API_URL=https://uxqxypf3p4.execute-api.us-east-1.amazonaws.com/dev \
  --dart-define=AWS_REGION=us-east-1 \
  --dart-define=COGNITO_USER_POOL_ID=us-east-1_TrwHCKjHA \
  --dart-define=COGNITO_APP_CLIENT_ID=412n6o2tfbd0uiv80i4733n0l0 \
  --dart-define=COGNITO_DOMAIN=https://roster-dev-dhjw6acs.auth.us-east-1.amazoncognito.com \
  --dart-define=COGNITO_REDIRECT_URI=rosterchamp://auth
```

Build (release APK):

```bash
flutter build apk --release \
  --dart-define=AWS_API_URL=https://uxqxypf3p4.execute-api.us-east-1.amazonaws.com/dev \
  --dart-define=AWS_REGION=us-east-1 \
  --dart-define=COGNITO_USER_POOL_ID=us-east-1_TrwHCKjHA \
  --dart-define=COGNITO_APP_CLIENT_ID=412n6o2tfbd0uiv80i4733n0l0 \
  --dart-define=COGNITO_DOMAIN=https://roster-dev-dhjw6acs.auth.us-east-1.amazoncognito.com \
  --dart-define=COGNITO_REDIRECT_URI=rosterchamp://auth
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
