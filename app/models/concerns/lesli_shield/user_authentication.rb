# frozen_string_literal: true

module LesliShield
    # Installs Shield's Devise-based authentication implementation on the core
    # user model. Lesli itself only consumes current_user and remains free of a
    # direct dependency on this engine or on Devise.
    module UserAuthentication
        extend ActiveSupport::Concern

        # This module is prepended after Devise installs its model modules so
        # LesliShield can extend, rather than replace, Devise's eligibility
        # checks. Calling super preserves confirmable, lockable, and any other
        # authentication provider rules.
        module LoginEligibility
            def active_for_authentication?
                super && lesli_shield_login_validation.valid?
            end

            def inactive_message
                return super if lesli_shield_login_validation.valid?

                :invalid
            end

            private

            def lesli_shield_login_validation
                return @lesli_shield_login_validation if defined?(
                    @lesli_shield_login_validation
                )

                @lesli_shield_login_validation = LesliShield::UserValidatorService
                    .new(self)
                    .validate
            end
        end

        DEVISE_MODULES = %i[
            database_authenticatable
            registerable
            rememberable
            recoverable
            validatable
            confirmable
            trackable
            lockable
        ].freeze

        included do
            devise(*LesliShield::UserAuthentication::DEVISE_MODULES)
            prepend LesliShield::UserAuthentication::LoginEligibility
        end
    end
end
