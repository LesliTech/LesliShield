<div class="documentation-header">
	<img alt="Lesli Shield logo" src="../app/assets/images/lesli_shield/shield-logo.svg" />
    <h1>Authentication & Authorization Management for the Lesli Framework</h1>
</div>

<div class="documentation-statics">
    <a target="blank" href="https://rubygems.org/gems/lesli_shield">
        <img src="https://badge.fury.io/rb/lesli_shield.svg" alt="Gem Version" height="24">
    </a>
</div>

### Quick start

```shell
# Add LesliShield engine
bundle add lesli_shield
```

```shell
# Setup database
rake lesli:db:setup
```

```ruby
# Load LesliShield
Rails.application.routes.draw do
    mount LesliShield::Engine => "/shield"
end
```
