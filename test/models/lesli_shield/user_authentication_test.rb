require "test_helper"

module LesliShield
    class UserAuthenticationTest < ActiveSupport::TestCase
        Role = Struct.new(:active)

        class RoleCollection
            def initialize(active:)
                @role = Role.new(active)
            end

            def exists?(attributes = nil)
                return true unless attributes

                attributes.all? do |name, value|
                    @role.public_send(name) == value
                end
            end
        end

        class DeviseUser
            attr_reader :account, :locked_until, :roles

            def initialize(
                devise_active: true,
                shield_active: true,
                account: Object.new,
                active_role: true,
                locked_until: nil
            )
                @devise_active = devise_active
                @shield_active = shield_active
                @account = account
                @locked_until = locked_until
                @roles = RoleCollection.new(active: active_role)
            end

            def active_for_authentication?
                @devise_active
            end

            def inactive_message
                :devise_inactive
            end

            def active?
                @shield_active
            end

            prepend LesliShield::UserAuthentication::LoginEligibility
        end

        test "accepts a user allowed by Devise and LesliShield" do
            assert DeviseUser.new.active_for_authentication?
        end

        test "preserves a rejection from Devise" do
            user = DeviseUser.new(devise_active: false)

            refute user.active_for_authentication?
            assert_equal :devise_inactive, user.inactive_message
        end

        test "rejects a user without an active role" do
            user = DeviseUser.new(active_role: false)

            refute user.active_for_authentication?
            assert_equal :invalid, user.inactive_message
        end

        test "rejects a user without an account" do
            user = DeviseUser.new(account: nil)

            refute user.active_for_authentication?
            assert_equal :invalid, user.inactive_message
        end

        test "installs the eligibility extension before Devise modules" do
            eligibility_index = Lesli::User.ancestors.index(
                LesliShield::UserAuthentication::LoginEligibility
            )
            authenticatable_index = Lesli::User.ancestors.index(
                Devise::Models::Authenticatable
            )

            assert eligibility_index
            assert authenticatable_index
            assert_operator eligibility_index, :<, authenticatable_index
        end
    end
end
