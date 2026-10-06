# Translations

LesliShield currently ships English and Spanish locale files. Engine-owned labels belong below the `lesli_shield` namespace; Devise screen labels are grouped by the screen bucket used by the views.

```yaml
en:
  lesli_shield:
    roles:
      title: "Roles"
    devise/sessions:
      view_title: "Welcome to Lesli"
```

Use complete I18n keys in Ruby:

```ruby
I18n.t("lesli_shield.roles.title")
```

Keep feature keys inside stable buckets such as `roles`, `users`, `invites`, or `shared`. Authentication templates also use bucket names such as `devise/sessions` and `devise/registrations`; preserve those names when adding copy for an existing screen.

Add every new key to both `config/locales/translations.en.yml` and `config/locales/translations.es.yml`, preserve interpolation variables, and render dynamic values through I18n rather than embedding them in translated strings.

When LesliBabel is installed:

```shell
bin/rails lesli_babel:scan
bin/rails lesli_babel:import
```

Review generated changes before committing them. The locale files in LesliShield remain the source distributed with the gem.
