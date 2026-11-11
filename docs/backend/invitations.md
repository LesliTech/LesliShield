# Account invitations

An account invitation is not a user. Creating, sending, resending, expiring,
or cancelling an invitation must never create or modify a `Lesli::User`.

## Lifecycle

Invitations use the following transitions:

```text
pending -> accepted
pending -> cancelled
pending -> expired
expired -> pending (resend only)
```

`accepted` and `cancelled` are terminal. This makes acceptance a one-time
operation. A pending invitation remains acceptable only while `expires_at` is
in the future.

The expiration period is configured with
`Lesli.config.shield[:invitation_expiration]` and defaults to seven days.

## User creation invariant

The recipient owns no `Lesli::User` created by the invitation until they open
the signed link, provide the required profile information and password, and
submit the acceptance form successfully.

Acceptance creates the user, assigns the existing account and selected role,
confirms the email, and marks the invitation as accepted in one transaction.
If any operation fails, no user is persisted and the invitation remains
pending.

`LesliShield::InvitationService` is the single mutation boundary for this
flow. It exposes `create_and_send!`, `resend!`, `cancel!`, and `accept!` so
controllers never change lifecycle state directly.

Acceptance locks the invitation and selected role before rechecking the
policy. This prevents two requests from accepting the same invitation and
ensures a role cannot be replaced or disabled unnoticed while the user is
being provisioned.

## Existing email policy

The email policy is evaluated both before delivery and again during acceptance:

- A member of the destination account is rejected.
- A user belonging to another account is rejected.
- An unconfirmed user without an account may be recovered only during secure
  acceptance.
- A deleted user is rejected and reported to the administrator.
- A confirmed user without an account is rejected for manual review.

The invite model performs the first evaluation when the invitation is created.
The acceptance service must repeat it inside the acceptance transaction; the
initial validation cannot prevent another process from creating a user later.

## Administrative action

The primary administrative operation is **Create and send invitation**. The
service creates the invitation in a transaction, generates a purpose-bound
signed link with the `:account_invitation` purpose, a maximum lifetime of seven
days, and a lifetime that cannot exceed `expires_at`. Delivery is scheduled
only after the transaction commits. Resending performs the same policy and role
checks before renewing the expiration and scheduling a new message.

Resolving the token also requires a pending invitation without acceptance or
cancellation timestamps, an active destination account, and an existing active
role that still belongs to that account. Acceptance repeats these checks while
holding database locks on the invitation, account, and role.

The signed link opens the public invitation form. The invited address is
readonly; the recipient supplies their profile and password. Invalid,
expired, cancelled, and already accepted links return `404` and cannot create
or modify a user.
