# Hybrid Identity Architecture

**Author:** Nikhil Mahtani · IT Systems Administrator  
**Environment:** Contoso Corp · contoso.local (on-prem) / contoso.com (cloud)

---

## Overview

This document covers the design decisions behind the hybrid identity setup used in this project. The goal is a single identity per user that works seamlessly both on-premises and in Microsoft 365 cloud services, managed from a single point of control.

---

## Identity Flow

```
On-premises AD (contoso.local)
        │
        │  Entra Connect (sync every 30 min)
        ▼
Entra ID / Azure Active Directory (contoso.com)
        │
        ├── Microsoft 365 (Exchange Online, Teams, SharePoint)
        ├── Microsoft Intune (device compliance)
        └── Conditional Access (policy enforcement)
```

---

## UPN Suffix Strategy

The on-premises domain uses `.local` which is not routable on the internet. A separate UPN suffix must be configured to match the public domain.

| Identity | Value |
|---|---|
| On-prem forest | `contoso.local` |
| On-prem UPN suffix | `@contoso.com` (added as alternate UPN suffix) |
| Entra ID tenant | `contoso.onmicrosoft.com` |
| Custom verified domain | `contoso.com` |

All user accounts are created with `UPN = firstname.lastname@contoso.com`, matching the verified Entra ID domain. This ensures SSO works without UPN rewrite rules in Entra Connect.

---

## Entra Connect Configuration

### Authentication Method: Password Hash Sync (PHS)

PHS was chosen over Pass-Through Authentication (PTA) for the following reasons:

| Factor | PHS | PTA |
|---|---|---|
| On-prem dependency at login | None | Requires on-prem agent |
| Cloud resilience | Full (users can log in even if on-prem is down) | Partial |
| Password hash exposure | Hash synced (never plaintext) | No hash in cloud |
| Leaked credential detection (Entra ID Protection) | Supported | Not supported |
| Complexity | Low | Medium (requires PTA agents) |

For a small-to-medium environment without strict regulatory requirements around credential storage, PHS provides the best balance of resilience and features.

---

## Sync Scope

Only selected OUs are synced to Entra ID. This reduces the attack surface and keeps service accounts and admin accounts cloud-free.

| OU | Synced | Reason |
|---|---|---|
| `Users\Employees\*` | Yes | Active employees need M365 access |
| `Groups\Security` | Yes | Used for Conditional Access and Intune targeting |
| `Users\ServiceAccounts` | No | Service accounts should not have cloud identities |
| `Users\Disabled` | No | Offboarded users should not sync |
| `Admin` | No | Privileged accounts must not exist in Entra ID |
| `Computers` | No | Device identity managed by Intune/Autopilot |

---

## Sync Interval

Entra Connect runs a delta sync every 30 minutes by default. For immediate sync after user creation or modification, the `Invoke-EntraSync.ps1` script triggers a manual delta cycle.

Full sync is only triggered manually after structural changes (new OUs added to sync scope, connector space cleanup).

---

## Writeback Features

| Feature | Enabled | Notes |
|---|---|---|
| Password writeback | Yes | Allows self-service password reset in Entra ID to write back to on-prem AD |
| Group writeback | No | Distribution groups managed on-prem only |
| Device writeback | No | Device identity managed via Intune |

Password writeback requires Entra ID P1 license and is essential for self-service password reset to work for hybrid users.

---

## Conditional Access Integration

Entra ID Conditional Access policies apply to all synced users. Key policies:

| Policy | Condition | Action |
|---|---|---|
| Require MFA for all users | Any app, any location | Require MFA |
| Block legacy authentication | Legacy auth protocols | Block |
| Require compliant device | M365 apps | Require Intune-compliant device |
| Block high-risk sign-ins | Entra ID Protection risk = High | Block |

Compliant device enforcement links this hybrid identity setup directly to the Intune MDM deployment in [intune-device-management](../intune-device-management).

---

## Entra Connect Server

Entra Connect is installed on a **dedicated member server** (`ENTRACONNECT01`), not on a domain controller. This is a Microsoft best practice — running Entra Connect on a DC increases the attack surface of the most critical server in the domain.

| Spec | Value |
|---|---|
| OS | Windows Server 2022 Standard |
| Role | Member server (no AD DS role) |
| Entra Connect version | Latest stable (auto-update enabled) |
| SQL | LocalDB (sufficient for < 100,000 objects) |
| Staging mode server | ENTRACONNECT02 (warm standby) |

---

## Offboarding Flow

When an employee leaves:

1. AD account disabled and moved to `OU=Disabled`
2. User removed from all security groups
3. Entra Connect delta sync runs — account disabled in Entra ID within 30 min
4. All active sessions revoked via `Revoke-MgUserSignInSession`
5. M365 license unassigned (mailbox converted to shared if needed)
6. After 30 days, account deleted from AD (and hard-deleted from Entra ID via sync)

The `OU=Disabled` OU is excluded from sync scope, so disabled accounts stop syncing immediately on move.
