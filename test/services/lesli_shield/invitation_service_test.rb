# frozen_string_literal: true

require "test_helper"
require "uri"

module LesliShield
    class InvitationServiceTest < ActiveSupport::TestCase
        include ActiveJob::TestHelper

        setup do
            clear_enqueued_jobs
            clear_performed_jobs
            ActionMailer::Base.deliveries.clear

            @context = insert_account_context
            @service = InvitationService.new(@context.fetch(:owner))
        end

        test "creates and queues a normalized invitation without creating a user" do
            invited_email = " New.Person.#{SecureRandom.hex(4)}@Example.COM "

            assert_no_difference -> { Lesli::User.count } do
                assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
                    @invitation = @service.create_and_send!(
                        email: invited_email,
                        full_name: "New Person",
                        role_id: @context.fetch(:target_role).id
                    )
                end
            end

            assert @invitation.persisted?
            assert @invitation.pending?
            assert_equal invited_email.strip.downcase, @invitation.email
            assert_equal @context.fetch(:shield_account), @invitation.account
            assert_equal @context.fetch(:owner), @invitation.invited_by
            assert_equal @context.fetch(:target_role), @invitation.role
            assert @invitation.sent_at.present?
            assert @invitation.expires_at.future?
        end

        test "delivers a signed acceptance link after the transaction commits" do
            invitation = nil

            perform_enqueued_jobs do
                invitation = @service.create_and_send!(
                    email: unique_email("mail"),
                    role_id: @context.fetch(:target_role).id
                )
            end

            mail = ActionMailer::Base.deliveries.last
            assert_equal [invitation.email], mail.to
            assert_equal I18n.t("lesli_shield.invites.mailer_subject"), mail.subject

            acceptance_url = URI.extract(mail.text_part.body.to_s, %w[http https]).first
            token = Rack::Utils.parse_query(URI(acceptance_url).query)
                .fetch("invitation_token")

            assert_equal invitation, @service.invitation_from_token!(token)
        end

        test "rejects members and roles that the inviter cannot assign" do
            assert_no_difference -> { Invite.count } do
                assert_no_enqueued_jobs do
                    assert_raises(ActiveRecord::RecordInvalid) do
                        @service.create_and_send!(
                            email: @context.fetch(:owner).email,
                            role_id: @context.fetch(:target_role).id
                        )
                    end
                end
            end

            elevated_role = insert_role(
                name: "elevated",
                permission_level: 101
            )

            assert_no_difference -> { Invite.count } do
                assert_raises(ActiveRecord::RecordNotFound) do
                    @service.create_and_send!(
                        email: unique_email("elevated"),
                        role_id: elevated_role.id
                    )
                end
            end
        end

        test "resends only expired invitations and renews their expiration" do
            invitation = insert_invitation(
                email: unique_email("expired"),
                status: :expired,
                expires_at: 1.hour.ago
            )

            travel_to Time.zone.local(2026, 11, 11, 12, 0, 0) do
                assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
                    @service.resend!(invitation)
                end

                invitation.reload
                assert invitation.pending?
                assert_equal Invite.expiration_period.from_now,
                    invitation.expires_at
                assert_equal Time.current, invitation.sent_at
            end

            assert_raises(Invite::InvalidStatusTransition) do
                @service.resend!(invitation)
            end
        end

        test "cancels a pending invitation without sending another email" do
            invitation = insert_invitation(email: unique_email("cancel"))

            assert_no_enqueued_jobs do
                @service.cancel!(invitation)
            end

            invitation.reload
            assert invitation.cancelled?
            assert invitation.cancelled_at.present?
        end

        test "accepts once by creating confirming and assigning the invited user" do
            invitation = insert_invitation(email: unique_email("accept"))
            token = acceptance_token(invitation)

            assert_difference -> { Lesli::User.count }, 1 do
                assert_difference -> { User::Role.count }, 1 do
                    @accepted_user = @service.accept!(
                        token: token,
                        user_attributes: valid_user_attributes
                    )
                end
            end

            invitation.reload
            assert invitation.accepted?
            assert_equal @accepted_user, invitation.accepted_user
            assert invitation.accepted_at.present?
            assert_equal @context.fetch(:account), @accepted_user.account
            assert_equal [@context.fetch(:target_role)], @accepted_user.roles.to_a
            assert @accepted_user.confirmed?
            assert_nil @accepted_user.confirmation_token
            assert_nil @accepted_user.confirmation_sent_at

            assert_no_difference -> { Lesli::User.count } do
                assert_raises(ActiveRecord::RecordInvalid) do
                    @service.accept!(
                        token: token,
                        user_attributes: valid_user_attributes
                    )
                end
            end
        end

        test "recovers the same unconfirmed user only during acceptance" do
            email = unique_email("recover")
            recoverable_user = Lesli::User.new(
                email: email,
                password: "old-password-123",
                password_confirmation: "old-password-123"
            )
            recoverable_user.skip_confirmation_notification!
            recoverable_user.save!

            invitation = insert_invitation(email: email)

            assert_no_difference -> { Lesli::User.count } do
                accepted_user = @service.accept!(
                    token: acceptance_token(invitation),
                    user_attributes: valid_user_attributes
                )

                assert_equal recoverable_user.id, accepted_user.id
            end

            recoverable_user.reload
            assert_equal @context.fetch(:account), recoverable_user.account
            assert_equal [@context.fetch(:target_role)], recoverable_user.roles.to_a
            assert recoverable_user.confirmed?
        end

        test "rolls back user role and invitation when acceptance is invalid" do
            invitation = insert_invitation(email: unique_email("rollback"))
            original_user_role_count = User::Role.count

            assert_no_difference -> { Lesli::User.count } do
                assert_raises(ActiveRecord::RecordInvalid) do
                    @service.accept!(
                        token: acceptance_token(invitation),
                        user_attributes: valid_user_attributes.merge(
                            password_confirmation: "different-password"
                        )
                    )
                end
            end

            assert_equal original_user_role_count, User::Role.count
            invitation.reload
            assert invitation.pending?
            assert_nil invitation.accepted_user
            assert_nil invitation.accepted_at
        end

        private

        def insert_account_context
            identifier = SecureRandom.hex(6)
            timestamp = Time.current
            account_id = Lesli::Account.insert_all!([{
                email: "account-#{identifier}@example.com",
                name: "Invitation account #{identifier}",
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
                uid: "OWNER-#{identifier}",
                email: "owner-#{identifier}@example.com",
                encrypted_password: "",
                active: true,
                confirmed_at: timestamp,
                sign_in_count: 0,
                failed_attempts: 0,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            owner_role = insert_role(
                account_id: account_id,
                name: "owner-#{identifier}",
                permission_level: 100
            )
            target_role = insert_role(
                account_id: account_id,
                name: "member-#{identifier}",
                permission_level: 50
            )

            User::Role.insert_all!([{
                user_id: owner_id,
                role_id: owner_role.id,
                created_at: timestamp,
                updated_at: timestamp
            }])

            {
                account: Lesli::Account.find(account_id),
                shield_account: Account.find(shield_account_id),
                owner: Lesli::User.find(owner_id),
                owner_role: owner_role,
                target_role: target_role
            }
        end

        def insert_role(
            account_id: @context&.fetch(:account)&.id,
            name:,
            permission_level:,
            active: true
        )
            timestamp = Time.current
            role_id = Lesli::Role.insert_all!([{
                account_id: account_id,
                name: name,
                code: "#{name}-#{SecureRandom.hex(3)}",
                permission_level: permission_level,
                active: active,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            Lesli::Role.find(role_id)
        end

        def insert_invitation(email:, status: :pending, expires_at: 1.day.from_now)
            timestamp = Time.current
            invitation_id = Invite.insert_all!([{
                account_id: @context.fetch(:shield_account).id,
                invited_by_id: @context.fetch(:owner).id,
                role_id: @context.fetch(:target_role).id,
                email: email,
                status: Invite.statuses.fetch(status.to_s),
                expires_at: expires_at,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            Invite.find(invitation_id)
        end

        def acceptance_token(invitation)
            invitation.signed_id(
                purpose: InvitationService::ACCEPTANCE_PURPOSE,
                expires_in: 1.day
            )
        end

        def valid_user_attributes
            {
                first_name: "Invited",
                last_name: "Person",
                telephone: "+502 5555 5555",
                password: "password-123",
                password_confirmation: "password-123"
            }
        end

        def unique_email(prefix)
            "#{prefix}-#{SecureRandom.hex(6)}@example.com"
        end
    end
end
