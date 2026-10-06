# Database

LesliShield uses collection code `08` and engine code `01`.

| Migration code | Table | Responsibility |
| --- | --- | --- |
| `08.01.00.01.10` | `lesli_shield_accounts` | Engine state for a Lesli account |
| `08.01.10.02.10` | `lesli_shield_role_actions` | Actions available to a core role |
| `08.01.10.04.10` | `lesli_shield_role_privileges` | Persisted privilege decisions for roles and resources |
| `08.01.11.01.10` | `lesli_shield_user_roles` | Membership between core users and roles |
| `08.01.11.10.10` | `lesli_shield_user_shortcuts` | Account-scoped navigation shortcuts for a user |
| `08.01.11.11.10` | `lesli_shield_user_tokens` | User authentication tokens |
| `08.01.11.12.10` | `lesli_shield_user_sessions` | Recorded user sessions |
| `08.01.12.01.10` | `lesli_shield_invites` | Invitations and their onboarding state |

Roles and users are owned by Lesli Core and referenced by these engine tables. The current migrations do not create Shield catalogs, workflows, role versions, user activities, attachments, or action tables.

Most security records use `deleted_at` for soft deletion. Preserve account ownership in every query and do not treat a soft-deleted role assignment, token, session, or invitation as active.

```shell
bin/rails lesli:db:prepare
bin/rails db:migrate:status
```

After schema or role changes, synchronize the derived privilege records with `bin/rails lesli_shield:privileges`. See [Database Architecture](/engines/lesli/database/structure) for account ownership and migration naming.
