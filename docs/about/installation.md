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
