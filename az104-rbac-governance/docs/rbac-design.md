# RBAC Design Decisions

This document explains the role strategy used in this project and the reasoning behind each design choice.

---

## Guiding Principles

**Least Privilege** — Every principal receives only the permissions required to do their job. No more.

**Scope at the lowest level** — Prefer resource group scope over subscription scope wherever possible. Subscription-level assignments are reserved for administrators.

**Prefer groups over individual users** — Assigning roles to Entra ID groups (not individual users) reduces management overhead and ensures consistent access during team changes.

**Custom roles for gap-filling only** — Built-in roles cover most scenarios. Custom roles are created only when a built-in role either over-grants or under-grants permissions for a specific use case.

---

## Role Matrix

| Persona              | Role                   | Scope              | Type    | Justification                                                      |
|----------------------|------------------------|--------------------|---------|---------------------------------------------------------------------|
| IT Admin             | Owner                  | Subscription       | BuiltIn | Full control needed for infrastructure management                   |
| Developer            | Contributor            | rg-dev             | BuiltIn | Needs to create/modify resources in dev only; no access to prod     |
| DevOps / CI-CD SP    | Contributor            | rg-staging         | BuiltIn | Service principal for pipeline deployments scoped to staging        |
| Operations           | VM Operator (Custom)   | rg-compute         | Custom  | Can operate VMs without risk of deletion or reconfiguration         |
| Auditor / Read-Only  | Reader                 | Subscription       | BuiltIn | Read-only visibility across all resources for compliance reviews    |
| Data Team            | Storage Blob Data Reader| rg-data           | BuiltIn | Scoped to data plane only; no control plane access                  |

---

## Why a Custom Role for VM Operator?

The closest built-in alternatives are:

| Role              | Problem                                                         |
|-------------------|-----------------------------------------------------------------|
| Contributor       | Too broad — can create, delete, and modify any resource        |
| Virtual Machine Contributor | Can create and delete VMs, and modify configurations |
| Reader            | Too narrow — cannot perform any operations                      |

**VM Operator (Custom)** fills the gap: operations staff can start/stop/restart VMs and read diagnostics, without the ability to create, delete, or reconfigure infrastructure.

---

## Subscription vs Resource Group Scope

Assignments at subscription scope propagate down to all resource groups via inheritance. This is appropriate for:
- Administrators who need cross-environment access
- Auditors who need read visibility everywhere

For all other personas, resource group scope is preferred to contain the blast radius of compromised credentials or misconfigured access.

---

## Service Principal for CI/CD

The DevOps pipeline uses a dedicated service principal (not a user account) assigned Contributor on the staging resource group. Key points:

- The SP has a certificate credential (not a password) rotated quarterly
- It is scoped to `rg-staging` only — it cannot touch production
- Production deployments require a separate approval-gated SP with a different credential

---

## AZ-104 Exam Notes

Key concepts this design maps to exam objectives:

- **Inherited vs direct assignments** — Reader on subscription scope is inherited by all RGs; VM Operator on rg-compute is direct.
- **AssignableScopes in custom roles** — The custom role is only usable within the defined subscription.
- **Actions vs NotActions** — NotActions are not a deny; they are exclusions from the Actions list. An explicit Deny assignment takes precedence over everything.
- **Owner vs User Access Administrator** — Both can assign roles, but Owner also has full resource access. Use User Access Administrator when you only need to delegate RBAC without granting resource control.
