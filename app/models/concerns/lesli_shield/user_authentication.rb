# frozen_string_literal: true

module LesliShield
    # Installs Shield's Devise-based authentication implementation on the core
    # user model. Lesli itself only consumes current_user and remains free of a
    # direct dependency on this engine or on Devise.
    module UserAuthentication
        extend ActiveSupport::Concern

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
        end
    end
end
