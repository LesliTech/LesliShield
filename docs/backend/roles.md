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

## Permission service

`LesliShield::RolePermissionService` owns permission selection through
`matrix`, `set!`, `duplicate_from!`, and `effective_permissions`.

The matrix begins with every non-deleted action whose parent resource is also
non-deleted. It left-joins the selected role actions so unassigned permissions
remain visible, groups resources by engine, and exposes readable labels
separately from technical engine, route, identifier, and action names. Standard
CRUD actions use a fixed order; custom actions follow alphabetically.

`set!(role:, action_id:, enabled:)` changes one permission selection. It locks
the role, revalidates the actor's account and permission boundary, validates
the submitted catalog ID, and activates or deactivates only that selection. A
real change updates `modified_at`; repeating the same state is a no-op, so it
does not create duplicate rows or update timestamps. Editing the selection is
not audited. The later deploy operation is audited because it changes the
permissions that authorize requests.

Saving selections does not rebuild the effective privilege cache.
`duplicate_from!` follows the same separation. Cache compilation remains an
explicit deploy operation because it is intentionally performed on demand.

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
| Enable one permission | `lesli_shield/role/actions#create` |
| Disable one permission | `lesli_shield/role/actions#destroy` |

Having one of these privileges never implies another. The nested permission
controller scopes the role to the current account and validates the submitted
ID against the active permission catalog before changing the selection.

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

Every visual checkbox is its own Rails `button_to` form. Enabling it sends
`POST /roles/:role_id/actions`; disabling it sends
`DELETE /roles/:role_id/actions/:id`. The server changes only that action, so a
request cannot replace changes made by another control. Turbo replaces the
permission matrix with the persisted server state and reports the result; this
feature has no page-specific JavaScript.

Editing a role's selected actions does not rebuild the effective privilege
cache automatically. Compilation is intentionally performed on demand through
the explicit `deploy` operation because rebuilding the cache can be expensive.

The role exposes its deployment state by comparing permission-specific
timestamps. `modified_at` records the last real selection change and
`deployed_at` records the last successful cache compilation. A role has pending
changes when `modified_at` is present and newer than `deployed_at`; `updated_at`
is deliberately ignored because ordinary role edits also change it.

The administrative interface at `/roles/:role_id/actions` shows all engines.
Each engine has a CRUD table followed by its custom actions, grouped by
resource. The module navigation filters this same view through URLs such as
`/roles/:role_id/actions/lesli-shield`. Engine slugs use the catalog's engine
name with underscores replaced by hyphens. Unknown engines return 404.
Both URLs use the same controller and `index` privilege. Search, permission
toggles, and deploy preserve the selected engine; deploy still compiles the
entire role.

Search is a regular `GET` form, and each permission toggle is persisted
immediately. On smaller screens each CRUD table row becomes a stacked resource
card, so horizontal scrolling is not required. Custom actions use responsive
cards and do not require nested accordions.

Deployment locks and revalidates the selected role, deletes the previous cache,
and rebuilds it completely from the active selection. Obsolete cache rows are
physically removed, including when the new selection is empty. Cache rebuild,
`deployed_at`, and the `role_privileges_deployed` audit event share one
transaction; a failed audit write restores the previous cache and timestamp.
Deployment has its own independent administrative privilege and remains
available through the dedicated deploy button.

## Administrative fields

The initial role administration UI exposes name, description, active state,
permission level, and default path. `isolated` and `path_limited` remain hidden
until their behavior is implemented, documented, and enforced by the
authorization layer.
