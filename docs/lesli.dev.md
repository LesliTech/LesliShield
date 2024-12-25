<p align="center">
	<img width="90" alt="Lesli Shield logo" src="../app/assets/images/lesli_shield/shield-logo.svg" />
    <h3 align="center">Authentication & Authorization for the Lesli Framework.</h3>
</p>

<hr/>
    <p align="center">
        <a target="blank" href="https://rubygems.org/gems/lesli_shield">
            <img src="https://badge.fury.io/rb/lesli_shield.svg" alt="Gem Version" height="24">
        </a>
    </p>
<hr/>

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
