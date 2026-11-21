require "test_helper"

module LesliShield
    class UserAuthenticationTest < ActiveSupport::TestCase
        test "Devise eligibility does not query Shield account or role rules" do
            user = Lesli::User.new(
                confirmed_at: Time.current,
                active: false,
                locked_until: 1.hour.from_now
            )
            user.define_singleton_method(:account) { raise "Unexpected account lookup" }
            user.define_singleton_method(:roles) { raise "Unexpected role lookup" }

            assert user.active_for_authentication?
        end

        test "preserves Devise confirmation requirements" do
            user = Lesli::User.new(confirmed_at: nil)

            refute user.active_for_authentication?
            assert_equal :unconfirmed, user.inactive_message
        end
    end
end
