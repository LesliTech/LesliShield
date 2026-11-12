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

## Role service

`LesliShield::RoleService` is the only role-administration entry point. It
provides `list`, `find!`, `create!`, `update!`, `deactivate!`, `destroy!`, and
`duplicate!`. Every operation applies account isolation and the actor's active
permission boundary before reading or changing a role.

Names and descriptions are normalized before persistence, and role names are
case-insensitively unique inside an account. New roles start active with a safe
permission level. A duplicated role starts inactive and copies only its active
selected actions; it never copies users, effective privilege cache rows, or
deployment state.

The list query supports name/description search, active/inactive filtering,
allowlisted ordering, and bounded pagination. User totals include only active,
non-deleted users with active assignments. Permission totals include only
non-deleted role actions.

## Administrative authorization

Every role lookup is scoped to `current_user.account.roles`. Direct access is
also limited to roles whose `permission_level` is no higher than the actor's
highest active level. A role outside either boundary returns `404`, including
when the submitted update attempts to raise a role above the boundary.

LesliShield's request authorization uses the following controller actions as
independent privileges:

| Operation | Required privilege |
| --- | --- |
| List roles | `lesli_shield/roles#index` |
| View a role | `lesli_shield/roles#show` |
| Create a role | `lesli_shield/roles#create` |
| Update or deactivate a role | `lesli_shield/roles#update` |
| Delete a role | `lesli_shield/roles#destroy` |
| Deploy effective privileges | `lesli_shield/roles#deploy` |
| View permissions | `lesli_shield/role/actions#index` |
| Add a permission | `lesli_shield/role/actions#update` |
| Remove a permission | `lesli_shield/role/actions#destroy` |

Having one of these privileges never implies another. The nested permission
controller loads every action through the selected role, so an action from a
different role or account is indistinguishable from a missing record.

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

Editing a role's selected actions does not rebuild the effective privilege
cache automatically. Compilation is intentionally performed on demand through
the explicit `deploy` operation because rebuilding the cache can be expensive.

Deployment locks the selected role and performs cache compilation together
with its `role_privileges_deployed` audit event in one transaction. A failed
audit write rolls the compilation and the role's `deployed_at` timestamp back.
Deployment has its own independent administrative privilege.

## Administrative fields

The initial role administration UI exposes name, description, active state,
permission level, and default path. `isolated` and `path_limited` remain hidden
until their behavior is implemented, documented, and enforced by the
authorization layer.
