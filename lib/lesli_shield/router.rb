# frozen_string_literal: true

module LesliShield
    module Router
        def self.mount_login_at(router, path = "")
            # Devise derives and memoizes the mapping strategies while
            # devise_for builds the routes. Install Shield's Devise modules
            # first so a cold application boot cannot produce an empty mapping.
            unless Lesli::User < LesliShield::UserAuthentication
                Lesli::User.include(LesliShield::UserAuthentication)
            end

            router.devise_for(
                :users,
                class_name: "Lesli::User",
                module: :devise,
                path: path,
                path_names: {
                    sign_in: "login",
                    sign_out: "logout",
                    sign_up: "register",
                    password: "password",
                    confirmation: "confirmation"
                },
                controllers: {
                    registrations: "users/registrations",
                    confirmations: "users/confirmations",
                    passwords: "users/passwords",
                    sessions: "users/sessions"
                }
            )

            configure_warden_user_mapping
        end

        def self.configure_warden_user_mapping
            mapping = Devise.mappings.fetch(:user)

            Devise.warden_config.scope_defaults(
                mapping.name,
                strategies: mapping.strategies
            )

            Devise.warden_config.serialize_into_session(mapping.name) do |record|
                mapping.to.serialize_into_session(record)
            end

            Devise.warden_config.serialize_from_session(mapping.name) do |args|
                mapping.to.serialize_from_session(*args)
            end
        end

        private_class_method :configure_warden_user_mapping
    end
end
