# SSH Plane Close Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop intentional member SSH closes from marking durable work-home down or showing the Android SSH disconnected banner; keep network-blip coalesce for storage (+ unexpected member) closes.

**Architecture:** Pure `SshTransportClosePolicy` decides whether a close affects durable home; coordinator consumes it; `SshConnectionCubit` and `SshHomeDisconnectedBanner` treat storage pool live as connected / hide banner.

**Tech Stack:** Flutter, dartssh2, existing `SshClientFactory` / coordinator / cubit, flutter_test.

**Spec:** `docs/superpowers/specs/2026-08-03-ssh-plane-close-policy-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/ssh/ssh_transport_close_policy.dart` | Policy decision type + evaluate |
| `client/test/services/ssh/ssh_transport_close_policy_test.dart` | Matrix unit tests |
| `client/lib/services/ssh/ssh_profile_connection_coordinator.dart` | Gate `_onTransportClosed` |
| `client/test/services/ssh/ssh_profile_connection_coordinator_test.dart` | Member intentional vs blip |
| `client/lib/cubits/ssh_connection_cubit.dart` | Live storage wins over reconnecting |
| `client/test/cubits/ssh_connection_cubit_test.dart` | Status after member-only close |
| `client/lib/widgets/ssh/ssh_home_disconnected_banner.dart` | Hide when storage live |
| `client/test/widgets/ssh/ssh_home_disconnected_banner_test.dart` | Member close does not show banner |

---

### Task 1: Policy unit tests + implementation

**Files:**
- Create: `ssh_transport_close_policy.dart` + test

- [ ] **Step 1: Failing policy matrix tests** covering memberSessionClosed → false; member remotePeerClosed → true; storage unexpected → true; expected local member → false.
- [ ] **Step 2: Implement `SshTransportClosePolicy.evaluate`.**
- [ ] **Step 3: `flutter test test/services/ssh/ssh_transport_close_policy_test.dart`**

### Task 2: Coordinator consumes policy

- [ ] **Step 1: Failing tests** — intentional member close keeps monitor healthy + pool live + no reconnect create; unexpected member close still downs; storage+member unexpected still coalesces once.
- [ ] **Step 2: Wire policy into `_onTransportClosed`.**
- [ ] **Step 3: Run coordinator tests.**

### Task 3: Cubit + banner storage-only

- [ ] **Step 1: Failing cubit/banner tests** — storage live ⇒ connected / banner hidden after member intentional close path.
- [ ] **Step 2: Fix `_resolveStatus` and banner live gate.**
- [ ] **Step 3: Run cubit + banner + full `test/services/ssh/` + related cubit tests.**

### Task 4: Verification

- [ ] `cd client && flutter test test/services/ssh/ test/cubits/ssh_connection_cubit_test.dart test/widgets/ssh/ssh_home_disconnected_banner_test.dart`
