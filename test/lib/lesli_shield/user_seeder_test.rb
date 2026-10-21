require "test_helper"

module LesliShield
    class UserSeederTest < ActiveSupport::TestCase
        test "adds Devise credentials to a user created by core" do
            account = create_account
            email = "shield-seed-#{SecureRandom.hex(4)}@example.com"
            password = "InitialPassword123!"
            timestamp = Time.current

            Lesli::User.insert_all!([{
                uid: "LID-#{SecureRandom.hex(4).upcase}",
                active: true,
                email: email,
                encrypted_password: "",
                account_id: account.id,
                created_at: timestamp,
                updated_at: timestamp
            }])

            user = Lesli::User.find_by!(email: email)

            assert_equal "", user.encrypted_password
            assert_respond_to user, :password=
            assert_respond_to user, :password_confirmation=
            assert_respond_to user, :skip_confirmation!

            user.password = password
            user.password_confirmation = password
            user.skip_confirmation!
            user.save!

            assert user.valid_password?(password)
            assert_predicate user, :confirmed?
        end

        test "supports idempotent role assignment for core seeds" do
            account = create_account
            user = Lesli::User.create!(
                account: account,
                email: "shield-role-seed-#{SecureRandom.hex(4)}@example.com",
                password: "InitialPassword123!",
                confirmed_at: Time.current
            )
            role = Lesli::Role.create!(
                account: account,
                active: true,
                name: "seed-role-#{SecureRandom.hex(4)}",
                permission_level: 10
            )

            2.times do
                user.user_roles.find_or_create_by!(role: role)
            end

            assert_equal 1, user.user_roles.where(role: role).count
        end

        private

        def create_account
            identifier = SecureRandom.hex(4)
            email = "shield-seed-account-#{identifier}@example.com"
            timestamp = Time.current

            Lesli::Account.insert_all!([{
                email: email,
                name: "Shield seed account",
                status: "active",
                created_at: timestamp,
                updated_at: timestamp
            }])

            Lesli::Account.find_by!(email: email)
        end
    end
end
