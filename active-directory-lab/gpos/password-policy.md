# GPO: Password Policy

**Linked to:** Domain root (`DC=contoso,DC=local`)  
**Scope:** All domain users  
**Author:** Nikhil Mahtani  

---

## Overview

The domain password policy enforces minimum password security requirements for all Active Directory accounts. It is linked at the domain root level and applies to every user in the domain.

Fine-Grained Password Policies (FGPP) are applied separately to the `Admin` OU and service accounts to enforce stricter requirements for privileged identities.

---

## Standard Policy (All Users)

Navigate to: `Computer Configuration → Windows Settings → Security Settings → Account Policies → Password Policy`

| Setting | Value | Reason |
|---|---|---|
| Enforce password history | 10 passwords | Prevents reuse of recent passwords |
| Maximum password age | 90 days | Regular rotation reduces exposure window |
| Minimum password age | 1 day | Prevents immediate re-use after reset |
| Minimum password length | 12 characters | Resists brute-force attacks |
| Password must meet complexity | Enabled | Requires uppercase, lowercase, number, symbol |
| Store passwords using reversible encryption | Disabled | Reversible encryption is a security risk |

Navigate to: `Computer Configuration → Windows Settings → Security Settings → Account Policies → Account Lockout Policy`

| Setting | Value | Reason |
|---|---|---|
| Account lockout threshold | 5 invalid attempts | Blocks brute-force without excessive disruption |
| Account lockout duration | 30 minutes | Auto-unlock after 30 min, reduces helpdesk calls |
| Reset account lockout counter after | 30 minutes | Resets failed attempt counter |

---

## Fine-Grained Password Policy — Admin Accounts

Applied via PSO (Password Settings Object) to the `Admin` OU and the `grp-domain-admins` group.

| Setting | Value |
|---|---|
| Minimum password length | 20 characters |
| Maximum password age | 30 days |
| Enforce password history | 24 passwords |
| Account lockout threshold | 3 invalid attempts |
| Account lockout duration | 60 minutes |
| Precedence | 10 (takes priority over domain policy) |

**PowerShell to apply FGPP:**

```powershell
New-ADFineGrainedPasswordPolicy `
    -Name "PSO-AdminAccounts" `
    -Precedence 10 `
    -MinPasswordLength 20 `
    -MaxPasswordAge "30.00:00:00" `
    -PasswordHistoryCount 24 `
    -LockoutThreshold 3 `
    -LockoutDuration "01:00:00" `
    -LockoutObservationWindow "01:00:00" `
    -ComplexityEnabled $true `
    -ReversibleEncryptionEnabled $false

Add-ADFineGrainedPasswordPolicySubject -Identity "PSO-AdminAccounts" -Subjects "grp-domain-admins"
```

---

## Fine-Grained Password Policy — Service Accounts

Applied via PSO to the `ServiceAccounts` OU.

| Setting | Value | Reason |
|---|---|---|
| Minimum password length | 30 characters | Long passphrase — managed by password vault |
| Maximum password age | Never expires | Managed rotation via PAM/password vault |
| Account lockout threshold | 0 (disabled) | Service accounts cannot be locked out |
| Precedence | 20 | |

---

## Notes

- Service account passwords are managed by a PAM solution, not manually reset.
- Admin accounts are separate from daily-use accounts (no admin tasks from standard UPN).
- All password changes are logged via Windows Security Event ID 4723 (user change) and 4724 (admin reset).
