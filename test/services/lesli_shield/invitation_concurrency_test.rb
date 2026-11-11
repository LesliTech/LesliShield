# frozen_string_literal: true

require "test_helper"

module LesliShield
    class InvitationConcurrencyTest < ActiveSupport::TestCase
        self.use_transactional_tests = false

        setup do
            @record_ids = Hash.new { |hash, key| hash[key] = [] }
            @context = insert_account_context
            @invitation = insert_invitation
            @token = @invitation.signed_id(
                purpose: InvitationService::ACCEPTANCE_PURPOSE,
                expires_in: 1.day
            )
        end

        teardown do
            cleanup_records
        end

        test "allows only one of two concurrent acceptance attempts" do
            ready = Queue.new
            start = Queue.new

            attempts = 2.times.map do
                Thread.new do
                    ActiveRecord::Base.connection_pool.with_connection do
                        ready << true
                        start.pop

                        begin
                            InvitationService.new(nil).accept!(
                                token: @token,
                                user_attributes: valid_user_attributes
                            )
                        rescue StandardError => exception
                            exception
                        end
                    end
                end
            end

            2.times { ready.pop }
            2.times { start << true }
            results = attempts.map(&:value)
            accepted_users = results.grep(Lesli::User)
            rejected_attempts = results.grep(Exception)

            assert_equal 1, accepted_users.length
            assert_equal 1, rejected_attempts.length
            assert_includes(
                [
                    ActiveRecord::RecordInvalid,
                    ActiveRecord::RecordNotUnique,
                    ActiveRecord::StatementInvalid
                ],
                rejected_attempts.first.class
            )
            assert_equal 1, Lesli::User.where(email: @invitation.email).count

            accepted_user = accepted_users.first.reload
            @record_ids[:users] << accepted_user.id
            @invitation.reload

            assert @invitation.accepted?
            assert_equal accepted_user, @invitation.accepted_user
            assert_equal @context.fetch(:account), accepted_user.account
            assert_equal [@context.fetch(:role)], accepted_user.roles.to_a
            assert accepted_user.confirmed?
        end

        private

        def insert_account_context
            identifier = SecureRandom.hex(8)
            timestamp = Time.current
            account_id = Lesli::Account.insert_all!([{
                email: "concurrent-account-#{identifier}@example.com",
                name: "Concurrent invitation #{identifier}",
                status: "active",
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            shield_account_id = Account.insert_all!([{
                account_id: account_id,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            owner_id = Lesli::User.insert_all!([{
                account_id: account_id,
                uid: "CONCURRENT-OWNER-#{identifier}",
                email: "concurrent-owner-#{identifier}@example.com",
                encrypted_password: "",
                active: true,
                confirmed_at: timestamp,
                sign_in_count: 0,
                failed_attempts: 0,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            role_id = Lesli::Role.insert_all!([{
                account_id: account_id,
                name: "concurrent-member-#{identifier}",
                code: "concurrent-member-#{identifier}",
                permission_level: 50,
                active: true,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            @record_ids[:accounts] << account_id
            @record_ids[:shield_accounts] << shield_account_id
            @record_ids[:users] << owner_id
            @record_ids[:roles] << role_id

            {
                account: Lesli::Account.find(account_id),
                shield_account: Account.find(shield_account_id),
                owner: Lesli::User.find(owner_id),
                role: Lesli::Role.find(role_id)
            }
        end

        def insert_invitation
            timestamp = Time.current
            invitation_id = Invite.insert_all!([{
                account_id: @context.fetch(:shield_account).id,
                invited_by_id: @context.fetch(:owner).id,
                role_id: @context.fetch(:role).id,
                email: "concurrent-invite-#{SecureRandom.hex(8)}@example.com",
                status: Invite.statuses.fetch("pending"),
                expires_at: 1.day.from_now,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            @record_ids[:invitations] << invitation_id

            Invite.find(invitation_id)
        end

        def valid_user_attributes
            {
                first_name: "Concurrent",
                last_name: "Invitee",
                password: "password-123",
                password_confirmation: "password-123"
            }
        end

        def cleanup_records
            accepted_user_ids = if @invitation
                Lesli::User.unscoped.where(email: @invitation.email).ids
            else
                []
            end
            @record_ids[:users] |= accepted_user_ids

            # All of these models use acts_as_paranoid. A regular delete_all
            # only marks some records as deleted, which leaves foreign keys
            # behind and contaminates the next fixture load.
            Invite.unscoped.where(id: @record_ids[:invitations]).delete_all!
            User::Role.unscoped.where(
                user_id: @record_ids[:users],
                role_id: @record_ids[:roles]
            ).delete_all!
            Lesli::User.unscoped.where(id: @record_ids[:users]).delete_all!
            Lesli::Role.unscoped.where(id: @record_ids[:roles]).delete_all!
            Account.unscoped.where(id: @record_ids[:shield_accounts]).delete_all!
            Lesli::Account.unscoped.where(id: @record_ids[:accounts]).delete_all!
        end
    end
end
