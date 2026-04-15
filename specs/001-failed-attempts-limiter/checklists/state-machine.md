# State Machine Checklist: Failed Attempts Limiter

**Purpose**: Validate state machine transition completeness and unambiguous coverage before implementation begins (pre-implementation author sanity check)
**Created**: 2026-04-15
**Feature**: [spec.md](../spec.md) · [data-model.md](../data-model.md)

---

## Transition Coverage

- [ ] CHK001 — Does `spec.md` define a requirement covering the `AuthError` → `AuthRateLimited` transition explicitly — i.e., does the 5th failure emit `AuthError` first, or jump directly to `AuthRateLimited`? The state machine diagram in `data-model.md` shows `AuthError` as an intermediate stop, but no FR in `spec.md` specifies the sequencing. [Completeness, Gap, Spec §FR-002]

- [ ] CHK002 — Is the `AppLocked` → `AuthLoading` → `AuthError` → `AuthRateLimited` path fully traced in `spec.md` with its own acceptance scenario? User Story 1 covers `Unauthenticated` → lockout, but no user story covers the `AppLocked` → lockout path specifically. [Coverage, Gap, Spec §User Story 1]

- [ ] CHK003 — Is the successor state after `AuthRateLimited` timer expiry (either `AppLocked` or `Unauthenticated`) specified as a _requirement_ in `spec.md`, or does it only appear in the Edge Cases section and `data-model.md`? Requirements and edge cases are separate; a behaviour this load-bearing should appear in an FR. [Completeness, Gap, Spec §Edge Cases]

- [ ] CHK004 — Are all transitions _out of_ `AuthRateLimited` enumerated and closed? The spec defines timer-expiry as an exit path; are there any other valid exits (e.g., app force-close, hardware error mid-lockout, lifecycle background event) that should either transition to another state or be explicitly excluded? [Coverage, Spec §FR-012]

- [ ] CHK005 — Is the `_preLockoutContext` derivation rule specified in `spec.md`, or only in `data-model.md`? Since this private enum determines which state follows `AuthRateLimited` expiry, its "set when `authenticate()` is called while in `AppLocked`" rule belongs in spec-level requirements, not only in design artefacts. [Completeness, Gap, Spec §FR-012]

- [ ] CHK006 — Does the state machine diagram in `data-model.md` cover the `BiometricNotAvailable` and `BiometricNotEnrolled` exit paths from `AuthLoading` initiated _while in `AppLocked`_? The diagram shows these states only from the initial `AuthInitial` path. [Consistency, Gap, data-model.md §State Machine]

---

## Context Preservation & Restoral

- [ ] CHK007 — Is there a requirement specifying what value `_preLockoutContext` takes on cold-start restore of an active lockout? `data-model.md` documents the default (`unauthenticated`), but `spec.md` contains no FR for this. Losing this rule means two implementations could legitimately diverge. [Completeness, Gap, data-model.md §Pre-Lockout Context]

- [ ] CHK008 — Is the acceptance scenario for User Story 4 (persistence) specific enough to cover the _context-restore_ case: that a user who was in `AppLocked` when the app was killed, relaunches to a lockout screen, waits for expiry, and ends up back at `AppLocked` (not `Unauthenticated`)? No current scenario tests this end-to-end path. [Coverage, Gap, Spec §User Story 4]

- [ ] CHK009 — Does `spec.md` define what happens to the in-memory `_preLockoutContext` during the `AuthRateLimited` timer if the app is backgrounded and resumed? Is the value re-derived from persisted state or held in memory? If it's memory-only, a background-kill mid-lockout would lose the context — and the fallback in `data-model.md` (default `unauthenticated`) would silently change behavior. [Completeness, Ambiguity, Spec §FR-008]

---

## Counter & Escalation Reset Semantics

- [ ] CHK010 — Is it unambiguously specified that `escalationLevel` does _not_ reset when the lockout timer expires (only when the user successfully authenticates)? FR-007 says "escalation resets on success", and FR-005 says only the _attempt counter_ resets on expiry — but no requirement explicitly states escalation is _not_ reset on expiry. An implementer reading the spec in isolation could infer otherwise. [Clarity, Ambiguity, Spec §FR-005, §FR-007]

- [ ] CHK011 — Does success criterion SC-003 ("no residual lockout state after successful auth") mean the `escalationLevel` is also cleared, or only the active lockout (`lockoutStartMs` / `lockoutDurationSeconds`)? "Residual lockout state" is not defined. If `escalationLevel` persists after success, SC-003 may give a false sense of a clean slate. [Clarity, Ambiguity, Spec §SC-003]

- [ ] CHK012 — Are the counter-increment and escalation-increment events specified as _atomic_ (both happen together on the 5th failure) or sequential? If they're sequential, what is the observable state between them? [Clarity, Spec §FR-002, §FR-006]

---

## Lifecycle Interaction

- [ ] CHK013 — Is the interaction between `LifecycleManager` auto-lock and an active `AuthRateLimited` state specified? Specifically: when the app is backgrounded while `AuthRateLimited` is emitted, does `handleAppPaused()` / `handleAppResumed()` attempt to emit `AppLocked`? The spec defines `AppLocked` as the lifecycle-resume state but does not exclude the `AuthRateLimited` case. [Coverage, Gap, Spec §FR-012, CLAUDE.md §LifecycleManager]

- [ ] CHK014 — Does `spec.md` define what the timer mechanism does when the app transitions to background? FR-003 requires countdown every second, and the edge case states elapsed background time must count. But neither specifies whether the `Timer.periodic` keeps firing in background, is paused, or is cancelled and recomputed on resume — leaving the _mechanism_ unspecified at the requirements level. [Clarity, Ambiguity, Spec §FR-003, §Edge Cases]

- [ ] CHK015 — Is there an acceptance scenario covering: _"Given the app is in `AuthRateLimited`, when backgrounded and the lockout expires while backgrounded, when the user resumes the app, then the app is in `AppLocked` or `Unauthenticated` (not still showing the lockout screen)"_? This background-expiry path has no scenario. [Coverage, Gap, Spec §User Story 2]

---

## Hardware & Error State Interactions

- [ ] CHK016 — Does the edge case "hardware unavailable mid-lockout" have a corresponding requirement? The edge case section states the lockout MUST still be enforced, but there is no FR number for this rule, making it non-binding and invisible to an implementer scanning the Requirements section only. [Completeness, Gap, Spec §Edge Cases]

- [ ] CHK017 — Are `BiometricNotAvailable` and `BiometricNotEnrolled` transitions specified for _both_ the `Unauthenticated` and `AppLocked` entry points? FR-011 says these events MUST NOT increment the counter, but does not specify which state the cubit returns to after such an event when called from `AppLocked`. [Completeness, Ambiguity, Spec §FR-011]

---

## Acceptance Scenario Traceability

- [ ] CHK018 — Does every FR (FR-001 through FR-012) trace to at least one acceptance scenario in a User Story? FR-010 (cancelled attempt doesn't increment) and FR-011 (hardware errors don't increment) have no dedicated acceptance scenarios — only prose requirements. [Traceability, Gap, Spec §FR-010, §FR-011]

- [ ] CHK019 — Is the acceptance scenario for User Story 3 (exponential backoff), Scenario 4 ("escalation resets after success, next lockout back to 60 s") specific about _when_ the reset is written to secure storage? The scenario tests observable duration but not the persistence of the reset, which matters for the bypass-resistance property. [Completeness, Spec §User Story 3 Scenario 4]

- [ ] CHK020 — Do the success criteria (SC-001 through SC-006) each trace back to at least one FR? SC-001 ("5 attempts in under 60 seconds of interaction time") and SC-002 ("countdown refreshes at least once per second") reference timing properties not directly anchored to an FR. [Traceability, Spec §SC-001, §SC-002]

---

## Boundary & Limit Definitions

- [ ] CHK021 — Is `kMaxFailedAttempts = 5` defined as a requirement in `spec.md` or only as a constant in `data-model.md`? FR-002 says "after exactly 5 consecutive failed attempts" inline, but the value is not extracted as a named threshold with its constraint rationale, making it harder to audit for future changes. [Clarity, Spec §FR-002]

- [ ] CHK022 — Is the backoff schedule `[60, 120, 240, 900]` defined as a requirement in `spec.md`? FR-006 states the sequence in prose ("60 s → 120 s → 240 s, capped at 900 s"), but the exact four-level list and clamping rule (`index clamped to list.length - 1`) appear only in `data-model.md`. If `data-model.md` is treated as a design artefact rather than a requirement, the clamping behaviour is unspecified. [Completeness, Ambiguity, Spec §FR-006]

- [ ] CHK023 — Are the `remainingSeconds` floor and ceiling bounds (clamped to [0, lockoutDurationSeconds]) specified as a requirement, or only documented in `data-model.md`? A negative `remainingSeconds` could be emitted if now exceeds lockoutStart + lockoutDuration, and the clamping rule is currently only in the data model. [Completeness, Gap, data-model.md §RateLimitRecord]

## Notes

- Focus: state machine transition completeness — does the spec fully and unambiguously define every valid state, every exit path from each state, and every condition that triggers a transition?
- Depth: pre-implementation author check — flag ambiguities before any code is written
- Audience: feature author (self-review before handing off to reviewer)
- Items marked `[Gap]` indicate a missing requirement; items marked `[Ambiguity]` indicate an existing requirement that needs tightening before it is implementable without guessing.
