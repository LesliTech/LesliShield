# Public registration and legal acceptance

LesliShield uses Devise for public registration, password validation, email
confirmation and rate limiting. The host application owns its legal documents.

## Configuration

Legal acceptance is disabled by default. Enable it in the host initializer:

```ruby
Lesli.configure do |config|
    config.shield.merge!(
        require_terms_acceptance: true,
        terms_url: "/terms",
        terms_version: "2026-11-20.1",
        privacy_url: "/privacy",
        privacy_version: "2026-11-20.1"
    )
end
```

Both URLs and both nonempty string versions are required when enabled. URLs may
be host paths or HTTPS links to the host's documents. Shield does not create the
pages. Incomplete configuration raises an explicit error on registration instead
of accepting empty versions. Document routes must be publicly accessible.

With the setting disabled, the generic form has no legal acceptance notice or
checkbox and signup does not record acceptance, even if a client submits those
fields. This setting is independent of `config.security[:allow_registration]`,
which controls whether public registration itself is available.

## Form and persistence

When enabled, the generic form renders an unchecked required checkbox and links
to both documents in new tabs. Server validation requires acceptance and checks
the submitted versions against the current configuration. HTML and Turbo retain
their existing form responses; this feature does not introduce a JSON registration
API. A JSON submission without acceptance also cannot create a user. A successful
signup stores these nullable Core user columns:

| Column | Meaning |
| --- | --- |
| `terms_accepted_at` | Server timestamp of acceptance during registration. |
| `terms_version` | Terms version accepted by the user. |
| `privacy_version` | Privacy notice version presented during registration. |

Recording the privacy version is not general consent to advertising, analytics
or other optional processing. Separate any additional consent required by the
host's actual practices.

Validation errors preserve the email and acceptance for the same versions, while
Devise clears passwords. Stale or missing versions require reviewing the current
documents and checking the box again. The server owns the timestamp and final
versions; the client cannot turn off validation.

Acceptance is required only during **public signup**. Existing users can log in
and update their information normally. Administrative creation, seeders and
invitations do not fabricate acceptance records. The setting does not add a
reacceptance flow or extend the invitation workflow.

## Host-specific wording

The generic checkbox has no age restriction. Override its label and validation
message through I18n when the host has additional eligibility requirements:

```yaml
es:
  overrides:
    lesli_shield:
      devise_registrations:
        label_terms_html: "Tengo 18 años o más y acepto los %{terms}."
        message_terms_required: "Debes confirmar que tienes 18 años o más y aceptas los términos."
```

Keep `%{terms}` in the label so Shield can insert the accessible link. This is a
user declaration, not identity or age verification. No copied registration view,
host model concern or controller override is necessary.

## Version changes and database setup

Increment the corresponding version whenever a document changes and preserve its
previous released text. Never update existing acceptance fields just because a
user logs in. A future reacceptance feature should retain an acceptance history.

New databases created from Core's original user migration include the three
columns. For an existing database, the host must add the nullable columns or
rebuild a disposable development/test database before enabling this feature.
The original migration change does not alter databases that already ran it.

Deploy matching public documents and configuration. Hosts that keep versions in
reloadable application constants can assign the settings inside
`Rails.application.config.to_prepare` so development reloads remain consistent.
