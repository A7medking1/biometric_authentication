<!--
SYNC IMPACT REPORT
==================
Version change: (none → 1.0.0) — Initial constitution; all placeholders replaced.

Modified principles: N/A (first version)

Added sections:
- Core Principles (I–V)
- Security Requirements
- Development Workflow
- Governance

Removed sections: N/A

Templates reviewed:
  ✅ .specify/templates/plan-template.md — "Constitution Check" gate is generic;
     no principle-specific references need updating.
  ✅ .specify/templates/spec-template.md — No constitution references found;
     no changes required.
  ✅ .specify/templates/tasks-template.md — No constitution references found;
     no changes required.
  ℹ  .specify/templates/commands/ — No command files found; nothing to update.

Deferred items: None. All placeholders resolved.
-->

# Biometric Authentication Constitution

## Core Principles

### I. Security-First Authentication

Biometric authentication MUST be the sole gateway to the app's protected content.
Authentication MUST NOT be bypassed, disabled via debug flags, or short-circuited
without an explicit, documented user action (e.g., a device that has no enrolled
biometrics surfaces a clear error state — not silent pass-through).

**Rationale**: The primary value proposition of this app is verified identity. Any
path that lets unauthenticated state render protected content violates the product's
security contract.

### II. Platform Abstraction

All platform-specific biometric plugin calls MUST be routed exclusively through
`LocalAuthService`. Direct invocation of the `local_auth` plugin or any native
plaftorm API outside that class is prohibited. `LocalAuthService.authenticate()`
MUST return a typed `LocalAuthResult` enum value — callers MUST NOT receive raw
platform booleans or exceptions.

**Rationale**: A single abstraction point allows platform mocking in tests and
future plugin migration without touching business logic.

### III. Explicit, Exhaustive State Machine

Every authentication state transition MUST be declared as a typed `AuthState`
subclass. `AuthCubit` MUST emit only documented states. Silent failures, implicit
default states, and catch-all fallbacks that swallow unhandled transitions are
prohibited. All states MUST be handled in every `BlocBuilder`/`BlocListener`.

**Rationale**: Unanticipated states rendered to the UI create unpredictable UX and
potential security holes (e.g., rendering protected content in an error branch).

### IV. Lifecycle Integrity (Auto-Lock)

The app MUST transition to `AppLocked` state when it resumes from the background
after exceeding the configured timeout (default: 3 seconds). `AppLocked` MUST be
a distinct state from `Unauthenticated`. `LifecycleManager` MUST invoke
`authCubit.handleAppPaused()` on pause and `authCubit.handleAppResumed()` on
resume — no other component may directly trigger the lock transition.

**Rationale**: Re-authentication after backgrounding prevents shoulder-surfing and
unauthorized device access. The `AppLocked` vs `Unauthenticated` distinction
preserves the prior-session context for UI messaging ("your session expired" vs
"please log in").

### V. Test-Driven State Logic

All `AuthCubit` state transitions MUST be covered by unit tests before the
corresponding implementation is merged. Widget tests MUST verify that `AuthGate`
renders the correct screen for every `AuthState` subclass. Tests MUST NOT mock
`AuthCubit` — use real cubit instances with a mocked `LocalAuthService`.

**Rationale**: Auth logic is security-critical; mocking the cubit would test only
the widget wiring, not the actual state machine correctness.

## Security Requirements

- `USE_BIOMETRIC` (Android) and `NSFaceIDUsageDescription` (iOS) MUST be declared
  in their respective manifests before any biometric API call is made.
- The app MUST NOT store biometric templates, raw sensor data, or session tokens
  in plain text on the device.
- Auth timeout MUST be configurable via a named constant — no magic numbers inline.
- Any new auth-adjacent feature (PIN fallback, remember-me, etc.) MUST be reviewed
  against Principles I–IV and documented as a constitution amendment if it
  introduces a new state or bypass path.

## Development Workflow

- Every PR MUST pass `flutter analyze` with zero errors and `flutter test` with
  zero failures before merge.
- Auto-fix lint issues with `dart fix --apply` before committing.
- New platform targets (e.g., Windows, macOS) MUST extend `LocalAuthService`
  with a corresponding `LocalAuthResult` mapping and accompanying unit tests.
- Build flavors (`development` / `production`) MUST NOT differ in authentication
  enforcement — only in app ID, display name, and environment endpoints.

## Governance

This constitution supersedes all other documented practices for this repository.
Any conflict between CLAUDE.md and this constitution MUST be resolved in favor
of this document, with CLAUDE.md updated to reflect the resolution.

**Amendment procedure**:

1. Open a PR with the proposed change to this file.
2. Increment `CONSTITUTION_VERSION` per semantic versioning:
   - MAJOR: principle removal, redefinition, or backward-incompatible governance change.
   - MINOR: new principle or section added / materially expanded.
   - PATCH: clarification, wording, or typo fix.
3. Update `LAST_AMENDED_DATE` to the merge date.
4. Propagate changes to affected templates and CLAUDE.md in the same PR.
5. All open specs and plans MUST be re-reviewed against updated principles before
   their next implementation task begins.

**Compliance**: All PRs and code reviews MUST verify compliance with the principles
above. Complexity or exceptions MUST be documented in the relevant plan's
"Complexity Tracking" table and justified against these principles.

**Version**: 1.0.0 | **Ratified**: 2026-04-14 | **Last Amended**: 2026-04-14
