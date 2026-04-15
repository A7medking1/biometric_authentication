# State Machine Checklist: Failed Attempts Limiter

**Purpose**: Validate state machine transition completeness and unambiguous coverage before implementation begins (pre-implementation author sanity check)
**Created**: 2026-04-15
**Feature**: [spec.md](../spec.md) · [data-model.md](../data-model.md)

---

## Transition Coverage

- [x] CHK001 — Does `spec.md` define a requirement covering the `AuthError` → `AuthRateLimited` transition explicitly — i.e., does the 5th failure emit `AuthError` first, or jump directly to `AuthRateLimited`? The state machine diagram in `data-model.md` shows `AuthError` as an intermediate stop, but no FR in `spec.md` specifies the sequencing. [Completeness, Gap, Spec §FR-002]
  **Resolved**: FR-002 now explicitly states the 5th failure emits `AuthRateLimited` directly — no intermediate `AuthError`. Failures 1–4 emit `AuthError`. `data-model.md` state machine diagram updated to match.

- [x] CHK002 — Is the `AppLocked` → `AuthLoading` → `AuthError` → `AuthRateLimited` path fully traced in `spec.md` with its own acceptance scenario? User Story 1 covers `Unauthenticated` → lockout, but no user story covers the `AppLocked` → lockout path specifically. [Coverage, Gap, Spec §User Story 1]
  **Resolved**: User Story 1 Scenario 5 added covering the `AppLocked` → lockout path with `_preLockoutContext = lifecycleLock`.

- [x] CHK003 — Is the successor state after `AuthRateLimited` timer expiry (either `AppLocked` or `Unauthenticated`) specified as a _requirement_ in `spec.md`, or does it only appear in the Edge Cases section and `data-model.md`? Requirements and edge cases are separate; a behaviour this load-bearing should appear in an FR. [Completeness, Gap, Spec §Edge Cases]
  **Resolved**: FR-013 added to spec.md: timer expiry → `AppLocked` if `lifecycleLock`, `Unauthenticated` if `unauthenticated`.

- [x] CHK004 — Are all transitions _out of_ `AuthRateLimited` enumerated and closed? The spec defines timer-expiry as an exit path; are there any other valid exits (e.g., app force-close, hardware error mid-lockout, lifecycle background event) that should either transition to another state or be explicitly excluded? [Coverage, Spec §FR-012]
  **Resolved**: FR-012 now explicitly closes the exit set: "The only valid exit from `AuthRateLimited` is countdown expiry. Force-closing, hardware errors, and lifecycle backgrounding do NOT exit the lockout state."

- [x] CHK005 — Is the `_preLockoutContext` derivation rule specified in `spec.md`, or only in `data-model.md`? Since this private enum determines which state follows `AuthRateLimited` expiry, its "set when `authenticate()` is called while in `AppLocked`" rule belongs in spec-level requirements, not only in design artefacts. [Completeness, Gap, Spec §FR-012]
  **Resolved**: FR-012 now includes the `_preLockoutContext` derivation rule (`lifecycleLock` when state is `AppLocked`, `unauthenticated` otherwise).

- [x] CHK006 — Does the state machine diagram in `data-model.md` cover the `BiometricNotAvailable` and `BiometricNotEnrolled` exit paths from `AuthLoading` initiated _while in `AppLocked`_? The diagram shows these states only from the initial `AuthInitial` path. [Consistency, Gap, data-model.md §State Machine]
  **Resolved**: `data-model.md` state machine diagram expanded to show `BiometricNotAvailable`/`BiometricNotEnrolled` returning to `AppLocked` when called from the `AppLocked` path.

---

## Context Preservation & Restoral

- [x] CHK007 — Is there a requirement specifying what value `_preLockoutContext` takes on cold-start restore of an active lockout? `data-model.md` documents the default (`unauthenticated`), but `spec.md` contains no FR for this. Losing this rule means two implementations could legitimately diverge. [Completeness, Gap, data-model.md §Pre-Lockout Context]
  **Resolved**: FR-009 now includes the cold-start default rule. Edge Cases section also amended with cold-start exception clause.

- [x] CHK008 — Is the acceptance scenario for User Story 4 (persistence) specific enough to cover the _context-restore_ case: that a user who was in `AppLocked` when the app was killed, relaunches to a lockout screen, waits for expiry, and ends up back at `AppLocked` (not `Unauthenticated`)? No current scenario tests this end-to-end path. [Coverage, Gap, Spec §User Story 4]
  **Resolved**: User Story 4 Scenario 4 added — covers `AppLocked` → lockout → force-kill → relaunch → expiry → `Unauthenticated` (cold-start rule; `_preLockoutContext` not persisted).

- [x] CHK009 — Does `spec.md` define what happens to the in-memory `_preLockoutContext` during the `AuthRateLimited` timer if the app is backgrounded and resumed? Is the value re-derived from persisted state or held in memory? If it's memory-only, a background-kill mid-lockout would lose the context — and the fallback in `data-model.md` (default `unauthenticated`) would silently change behavior. [Completeness, Ambiguity, Spec §FR-008]
  **Resolved**: Clarifications (Session 2026-04-15) now documents: `_preLockoutContext` is memory-only; survives background/resume; lost on force-kill; cold-start defaults to `unauthenticated`.

---

## Counter & Escalation Reset Semantics

- [x] CHK010 — Is it unambiguously specified that `escalationLevel` does _not_ reset when the lockout timer expires (only when the user successfully authenticates)? FR-007 says "escalation resets on success", and FR-005 says only the _attempt counter_ resets on expiry — but no requirement explicitly states escalation is _not_ reset on expiry. An implementer reading the spec in isolation could infer otherwise. [Clarity, Ambiguity, Spec §FR-005, §FR-007]
  **Resolved**: FR-005 now explicitly states "The escalation level (FR-007) is NOT reset on expiry — it persists until a successful authentication." FR-007 now says "ONLY upon successful authentication."

- [x] CHK011 — Does success criterion SC-003 ("no residual lockout state after successful auth") mean the `escalationLevel` is also cleared, or only the active lockout (`lockoutStartMs` / `lockoutDurationSeconds`)? "Residual lockout state" is not defined. If `escalationLevel` persists after success, SC-003 may give a false sense of a clean slate. [Clarity, Ambiguity, Spec §SC-003]
  **Resolved**: SC-003 now defines "residual lockout state" explicitly: includes active lockout fields, failed attempt count, and escalation level — all cleared on success.

- [x] CHK012 — Are the counter-increment and escalation-increment events specified as _atomic_ (both happen together on the 5th failure) or sequential? If they're sequential, what is the observable state between them? [Clarity, Spec §FR-002, §FR-006]
  **Resolved**: Edge Cases section now documents atomicity: "Both operations occur synchronously in the same event handler with no intermediate state observable between them." Clarifications also note this.

---

## Lifecycle Interaction

- [x] CHK013 — Is the interaction between `LifecycleManager` auto-lock and an active `AuthRateLimited` state specified? Specifically: when the app is backgrounded while `AuthRateLimited` is emitted, does `handleAppPaused()` / `handleAppResumed()` attempt to emit `AppLocked`? The spec defines `AppLocked` as the lifecycle-resume state but does not exclude the `AuthRateLimited` case. [Coverage, Gap, Spec §FR-012, CLAUDE.md §LifecycleManager]
  **Resolved**: FR-015 added — `handleAppResumed()` MUST NOT emit `AppLocked` while in `AuthRateLimited`. Clarifications note this is already satisfied by `_shouldRequireAuth()` returning false for non-`Authenticated` states.

- [x] CHK014 — Does `spec.md` define what the timer mechanism does when the app transitions to background? FR-003 requires countdown every second, and the edge case states elapsed background time must count. But neither specifies whether the `Timer.periodic` keeps firing in background, is paused, or is cancelled and recomputed on resume — leaving the _mechanism_ unspecified at the requirements level. [Clarity, Ambiguity, Spec §FR-003, §Edge Cases]
  **Resolved**: Edge Cases section now documents the timer mechanism: remaining time computed from `_lockoutStartMs` on every tick (not decremented), so missed background ticks cause no drift. Clarifications also cover this.

- [x] CHK015 — Is there an acceptance scenario covering: _"Given the app is in `AuthRateLimited`, when backgrounded and the lockout expires while backgrounded, when the user resumes the app, then the app is in `AppLocked` or `Unauthenticated` (not still showing the lockout screen)"_? This background-expiry path has no scenario. [Coverage, Gap, Spec §User Story 2]
  **Resolved**: User Story 2 Scenario 4 added covering background-expiry path.

---

## Hardware & Error State Interactions

- [x] CHK016 — Does the edge case "hardware unavailable mid-lockout" have a corresponding requirement? The edge case section states the lockout MUST still be enforced, but there is no FR number for this rule, making it non-binding and invisible to an implementer scanning the Requirements section only. [Completeness, Gap, Spec §Edge Cases]
  **Resolved**: FR-014 added — hardware becoming unavailable during `AuthRateLimited` MUST NOT reset, cancel, or bypass the lockout.

- [x] CHK017 — Are `BiometricNotAvailable` and `BiometricNotEnrolled` transitions specified for _both_ the `Unauthenticated` and `AppLocked` entry points? FR-011 says these events MUST NOT increment the counter, but does not specify which state the cubit returns to after such an event when called from `AppLocked`. [Completeness, Ambiguity, Spec §FR-011]
  **Resolved**: FR-011 now specifies: "When such an event occurs while the cubit state is `AppLocked`, the cubit MUST remain in `AppLocked`." User Story 1 Scenario 7 and T006(f) cover this case.

---

## Acceptance Scenario Traceability

- [x] CHK018 — Does every FR (FR-001 through FR-012) trace to at least one acceptance scenario in a User Story? FR-010 (cancelled attempt doesn't increment) and FR-011 (hardware errors don't increment) have no dedicated acceptance scenarios — only prose requirements. [Traceability, Gap, Spec §FR-010, §FR-011]
  **Resolved**: User Story 1 Scenarios 6 and 7 added as explicit acceptance scenarios for FR-010 and FR-011 respectively.

- [x] CHK019 — Is the acceptance scenario for User Story 3 (exponential backoff), Scenario 4 ("escalation resets after success, next lockout back to 60 s") specific about _when_ the reset is written to secure storage? The scenario tests observable duration but not the persistence of the reset, which matters for the bypass-resistance property. [Completeness, Spec §User Story 3 Scenario 4]
  **Resolved**: User Story 3 Scenario 4 amended to include: "The escalation reset is also persisted to secure storage so that a subsequent force-kill and relaunch also results in a 60-second first lockout."

- [x] CHK020 — Do the success criteria (SC-001 through SC-006) each trace back to at least one FR? SC-001 ("5 attempts in under 60 seconds of interaction time") and SC-002 ("countdown refreshes at least once per second") reference timing properties not directly anchored to an FR. [Traceability, Spec §SC-001, §SC-002]
  **Resolved**: SC-001 now cites FR-002; SC-002 now cites FR-003.

---

## Boundary & Limit Definitions

- [x] CHK021 — Is `kMaxFailedAttempts = 5` defined as a requirement in `spec.md` or only as a constant in `data-model.md`? FR-002 says "after exactly 5 consecutive failed attempts" inline, but the value is not extracted as a named threshold with its constraint rationale, making it harder to audit for future changes. [Clarity, Spec §FR-002]
  **Resolved**: FR-002 names the value inline ("exactly 5") and the Assumptions section documents it as a constant `kMaxFailedAttempts` that may be made configurable in a follow-up. No further extraction needed for v1.

- [x] CHK022 — Is the backoff schedule `[60, 120, 240, 900]` defined as a requirement in `spec.md`? FR-006 states the sequence in prose ("60 s → 120 s → 240 s, capped at 900 s"), but the exact four-level list and clamping rule (`index clamped to list.length - 1`) appear only in `data-model.md`. If `data-model.md` is treated as a design artefact rather than a requirement, the clamping behaviour is unspecified. [Completeness, Ambiguity, Spec §FR-006]
  **Resolved**: FR-006 now explicitly enumerates all four levels (0→60 s, 1→120 s, 2→240 s, 3+→900 s) and states the clamping rule as a requirement.

- [x] CHK023 — Are the `remainingSeconds` floor and ceiling bounds (clamped to [0, lockoutDurationSeconds]) specified as a requirement, or only documented in `data-model.md`? A negative `remainingSeconds` could be emitted if now exceeds lockoutStart + lockoutDuration, and the clamping rule is currently only in the data model. [Completeness, Gap, data-model.md §RateLimitRecord]
  **Resolved**: FR-003 now requires `remainingSeconds` to be clamped to [0, lockoutDurationSeconds] and MUST NOT be negative.

## Notes

- Focus: state machine transition completeness — does the spec fully and unambiguously define every valid state, every exit path from each state, and every condition that triggers a transition?
- Depth: pre-implementation author check — flag ambiguities before any code is written
- Audience: feature author (self-review before handing off to reviewer)
- Items marked `[Gap]` indicate a missing requirement; items marked `[Ambiguity]` indicate an existing requirement that needs tightening before it is implementable without guessing.
- **Status**: All 23 items resolved (2026-04-15). Spec and data-model updated. Ready for `/speckit-implement`.
