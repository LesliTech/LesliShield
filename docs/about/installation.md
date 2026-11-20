# Installation

LesliShield provides authentication, role-based authorization, invitations, and account-scoped security administration. It requires Lesli `~> 5.1.0`.

## Install and Mount

```shell
bundle add lesli_shield
```

The standard Lesli router configures the authentication routes and mounts the engine at `/shield`:

```ruby
Rails.application.routes.draw do
  Lesli::Router.mount(self)
end
```

For a manual installation, configure authentication before mounting the engine:

```ruby
Rails.application.routes.draw do
  LesliShield::Router.mount_login_at(self)
  mount LesliShield::Engine => "/shield"
end
```

Pass a path such as `"account"` to `mount_login_at` when the application should expose `/account/login`, `/account/logout`, and the related registration and password routes.

Prepare the database and initialize installed engines:

```shell
bin/rails lesli:db:prepare
```

## Verify the Installation

```shell
bin/rails routes -g login
bin/rails routes -g shield
bin/rails server
```

Visit `http://127.0.0.1:3000/shield`. After signing in, visit `/shield/profile` to verify the authenticated user's [self-service profile](/engines/shield/profile/overview).

Run the [privilege synchronization task](/engines/shield/about/tasks) after changing roles, actions, or protected resources.

## Authentication Background

Override Shield's images in the host application, just like the application logo.
Use these exact paths, including the `.webp` extension:

```text
app/assets/images/lesli_shield/login-background.webp
app/assets/images/lesli_shield/register-background.webp
```

The login screen uses `login-background.webp`; registration and invitation
acceptance use `register-background.webp`. Copy the same image to both paths to
share a background. Convert JPEG or PNG files to WebP instead of just renaming
their extension.

Rails gives host assets precedence over the engine's defaults. Propshaft resolves
the CSS references to fingerprinted asset URLs, including during production
precompilation. No initializer option or view override is needed. When an override
is absent, Shield's bundled image is used.

Images retain their natural colors, without a blue tint. The neutral gradient
behind the panel text remains for readability. Images use centered cover cropping,
and the panel stays hidden on smaller screens.

Existing host overrides named `login-background.jpg` or `register-background.jpg`
must be converted to the new WebP paths.

## Profile Timezone

Users choose an optional IANA timezone in their profile. Login does not detect,
submit or save the browser timezone. Core uses the profile preference, otherwise
`Lesli.config.datetime[:time_zone]`, then the Rails application timezone.
Timestamps remain stored in UTC. See [User Profile](/engines/shield/profile/overview).
