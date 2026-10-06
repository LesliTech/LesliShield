# Tasks

LesliShield exposes one supported maintenance task.

## Synchronize Privileges

```shell
bin/rails lesli_shield:privileges
```

The task loads every core role and asks `LesliShield::RolePrivilegeService` to synchronize its privilege records with the currently available role actions and protected resources.

| Property | Value |
| --- | --- |
| Environment | Any environment with the application and database loaded |
| Reads | Core roles, registered resources, and role actions |
| Writes | `lesli_shield_role_privileges` |
| Repeatability | Safe to repeat for the same registered inputs |

Run it after adding or removing protected controllers or actions, changing role-action definitions, or deploying authorization changes. It is also invoked by the standard `bin/rails lesli:db:prepare` workflow.

Review roles and registered resources before running the task in production. Synchronization is performed synchronously for every role.
