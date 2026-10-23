require "test_helper"

load Lesli::Engine.root.join("db", "seed", "xyz.rb")

module LesliShield
    class UserSeederTest < ActiveSupport::TestCase
        test "creates a user with Devise credentials and the requested role" do
            account = create_account
            email = "shield-seed-#{SecureRandom.hex(4)}@example.com"
            password = "InitialPassword123!"
            role = create_role(account, "owner")

            user = create_account_user(
                account: account,
                email: email,
                role_name: role.name,
                first_name: "Shield",
                last_name: "User",
                password: password
            )

            assert_respond_to user, :password=
            assert_respond_to user, :password_confirmation=
            assert_respond_to user, :skip_confirmation!
            assert user.valid_password?(password)
            assert_predicate user, :confirmed?
            assert_equal account, user.account
            assert_equal [role], user.roles.to_a
        end

        test "does not duplicate the user or role assignment" do
            account = create_account
            email = "shield-role-seed-#{SecureRandom.hex(4)}@example.com"
            password = "InitialPassword123!"
            role = create_role(account, "guest")

            2.times do
                create_account_user(
                    account: account,
                    email: email,
                    role_name: role.name,
                    first_name: "Shield",
                    last_name: "User",
                    password: password
                )
            end

            user = Lesli::User.find_by!(email: email)

            assert_equal 1, Lesli::User.where(email: email).count
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

        def create_role(account, name)
            Lesli::Role.create!(
                account: account,
                active: true,
                name: name,
                permission_level: 10
            )
        end
    end
end
