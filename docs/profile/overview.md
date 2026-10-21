# User Profile

LesliShield provides a self-service profile for every authenticated user. The profile is available at `/shield/profile` and always operates on the current user, so it does not accept a user ID and does not require administrative privileges.

Use the profile for personal account changes. Use the user administration screens when an authorized administrator needs to manage another user, their roles, or their privileges.

## Profile Information

The **Information** tab allows the current user to update these fields:

- Alias
- Title
- Email
- First name
- Last name
- Telephone

Account ownership, activation status, roles, privileges, and other administrative attributes cannot be changed through the profile.

When no alias is supplied, LesliShield generates one from the user's initials. Validation errors are displayed without persisting an incomplete update.

## Password

The **Security** tab allows the current user to change their password. The form requires:

- The current password
- A new password that satisfies the configured Devise password length
- Confirmation of the new password

After a successful change, LesliShield:

1. Clears `password_expiration_at`, when that attribute is available.
2. Refreshes the current Devise session so the user remains signed in.
3. Revokes the user's other tracked LesliShield sessions when the current session can be identified.
4. Records a successful password-change event through Lesli's logging interface.

Failed attempts are also logged and never include the submitted passwords. Password updates are limited to 10 attempts per user within 15 minutes. A limited request receives HTTP `429 Too Many Requests` and a `Retry-After` header.

## Routes

The paths below assume the engine is mounted at its default `/shield` location.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/shield/profile` | Show the current user's profile |
| `PATCH` or `PUT` | `/shield/profile` | Update the current user's profile information |
| `PATCH` or `PUT` | `/shield/profile/password` | Change the current user's password |

All three routes require authentication. They intentionally bypass role-based authorization because they can only access `current_user`.

Inside LesliShield, use `profile_path` and `profile_password_path`. From a host application, use the mounted engine proxy when one is available, for example:

```erb
<%= link_to "Profile", lesli_shield.profile_path %>
```

Lesli Core's application header automatically links to this profile when LesliShield is installed and the route is available.

## JSON Responses

Request JSON by sending `Accept: application/json`. The profile endpoint exposes only these fields:

```json
{
  "id": 1,
  "uid": "USR260ABC",
  "alias": "LU",
  "title": null,
  "email": "user@example.com",
  "first_name": "Lesli",
  "last_name": "User",
  "telephone": null
}
```

Update profile information with a `user` object:

```json
{
  "user": {
    "first_name": "Lesli",
    "last_name": "User",
    "telephone": "+502 5555 5555"
  }
}
```

Change the password with the current password and matching new-password values:

```json
{
  "user": {
    "current_password": "current-password",
    "password": "new-password",
    "password_confirmation": "new-password"
  }
}
```

A successful password change returns a localized `message`. Validation failures return HTTP `422 Unprocessable Content` with an `errors` object. Password values are never included in responses.

HTML and Turbo requests use the same validation and security rules. Successful HTML updates redirect with HTTP `303 See Other`; Turbo responses update the notification area and keep the user on the relevant profile tab.
