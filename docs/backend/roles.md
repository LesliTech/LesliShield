# Roles and permissions

Role administration is account-scoped. A role belongs to exactly one
`Lesli::Account`, and an administrator may manage a role only when both belong
to the same account and the role's `permission_level` is not higher than the
administrator's highest active level.

## Role categories

LesliShield recognizes `owner`, `admin`, and `guest` as system roles. System
roles are part of account initialization and cannot be deleted. The `owner`
role is additionally protected: it may be inspected, but it cannot be changed
through role administration.

Custom roles may be deleted only when they are inside the administrator's
management boundary and have no users assigned. Deletion rules must be checked
by the domain policy on every mutation; hiding a button is not authorization.

The policy is exposed by `LesliShield::RoleManagement` through:

- `system_role?`
- `protected_role?`
- `manageable_by?(actor)`
- `assigned?`
- `deletable_by?(actor)`

## Deactivation

Deactivation is reversible. Setting a role to inactive keeps its user-role
assignments and configured permissions, but those permissions stop
contributing to authorization immediately. Reactivating the role restores its
previous configuration without rebuilding the assignments.

## Permission catalog and application

`Lesli::Resource` is the canonical permission catalog. A role's action records
are selections from that catalog and must never be used as the catalog itself.
This guarantees that a newly created role can display every available action,
including actions it has never been granted.

Permission changes use an apply-on-save contract. The final save operation
must update the selected role actions and rebuild their effective privilege
cache in one transaction. Administrators must not perform a separate deploy
step. The existing deploy endpoint is transitional and will be removed when
the bulk permission service is implemented.

## Administrative fields

The initial role administration UI exposes name, description, active state,
permission level, and default path. `isolated` and `path_limited` remain hidden
until their behavior is implemented, documented, and enforced by the
authorization layer.
