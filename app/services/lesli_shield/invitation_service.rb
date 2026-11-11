# frozen_string_literal: true

module LesliShield
    # Owns every invitation lifecycle mutation that crosses model boundaries.
    # Administrative operations require an actor; public acceptance authenticates
    # the operation with the purpose-bound signed invitation token instead.
    class InvitationService < Lesli::ApplicationLesliService
        ACCEPTANCE_PURPOSE = :account_invitation
        TOKEN_LIFETIME = 7.days
        USER_ATTRIBUTES = %i[
            first_name
            last_name
            telephone
            password
            password_confirmation
        ].freeze

        def create_and_send!(attributes)
            invitation_attributes = attributes.to_h.symbolize_keys
            invitation_attributes[:email] = normalize_email(
                invitation_attributes[:email]
            )

            invitation = nil

            Invite.transaction do |transaction|
                shield_account = current_shield_account!
                role = assignable_role!(
                    shield_account,
                    invitation_attributes.delete(:role_id)
                )

                invitation = shield_account.invites.new(
                    invitation_attributes.slice(
                        :email,
                        :full_name,
                        :telephone,
                        :notes
                    )
                )
                invitation.invited_by = current_user
                invitation.role = role
                invitation.sent_at = Time.current
                invitation.save!

                enqueue_delivery_after_commit(
                    transaction,
                    invitation,
                    operation: :invitation_sent,
                    actor: current_user
                )
            end

            invitation
        end

        def resend!(invitation)
            resent_invitation = nil

            Invite.transaction do |transaction|
                resent_invitation = lock_owned_invitation!(invitation)
                validate_invitation_email!(resent_invitation)
                validate_assignable_role!(resent_invitation.role)

                if resent_invitation.pending? &&
                    !resent_invitation.acceptance_available?
                    resent_invitation.expire!
                end

                resent_invitation.resend!
                resent_invitation.update!(sent_at: Time.current)

                enqueue_delivery_after_commit(
                    transaction,
                    resent_invitation,
                    operation: :invitation_resent,
                    actor: current_user
                )
            end

            resent_invitation
        end

        def cancel!(invitation)
            cancelled_invitation = nil

            Invite.transaction do
                cancelled_invitation = lock_owned_invitation!(invitation)
                cancelled_invitation.cancel!
                record_audit_event!(
                    :invitation_cancelled,
                    cancelled_invitation,
                    actor: current_user
                )
            end

            cancelled_invitation
        end

        def accept!(token:, user_attributes:)
            accepted_user = nil

            Invite.transaction do
                invitation = lock_signed_invitation!(token)
                role = validate_token_constraints!(
                    invitation,
                    lock_associations: true
                )

                decision = locked_email_decision(invitation)
                validate_email_decision!(invitation, decision)

                accepted_user = build_or_recover_user(
                    invitation,
                    decision,
                    user_attributes
                )
                persist_user!(accepted_user)
                assign_role!(accepted_user, role)
                confirm_user!(accepted_user)
                invitation.accept!(accepted_user)
                record_audit_event!(
                    :invitation_accepted,
                    invitation,
                    actor: accepted_user
                )
            end

            accepted_user
        end

        def invitation_from_token!(token)
            invitation = signed_invitation!(token)
            validate_token_constraints!(invitation)
            invitation
        end

        def signed_acceptance_url(invitation)
            token = invitation.signed_id(
                purpose: ACCEPTANCE_PURPOSE,
                expires_in: signed_token_lifetime(invitation)
            )

            Rails.application.routes.url_helpers.user_invitation_url(
                **action_mailer_url_options,
                invitation_token: token
            )
        end

        private

        def normalize_email(email)
            email.to_s.strip.downcase.presence
        end

        def current_shield_account!
            current_user&.account&.shield || raise(ActiveRecord::RecordNotFound)
        end

        def assignable_role!(shield_account, role_id)
            invitation = shield_account.invites.new
            invitation.invited_by = current_user

            if role_id.blank?
                invalid_invitation!(
                    invitation,
                    :role,
                    I18n.t("lesli_shield.invites.role_required")
                )
            end

            role = shield_account.account.roles.find(role_id)
            return role if current_user.can_assign_role?(role)

            raise ActiveRecord::RecordNotFound
        end

        def validate_assignable_role!(role)
            return if current_user.can_assign_role?(role)

            raise ActiveRecord::RecordNotFound
        end

        def lock_owned_invitation!(invitation)
            current_shield_account!
                .invites
                .lock
                .find(invitation.id)
        end

        def lock_signed_invitation!(token)
            signed_invitation = signed_invitation!(token)
            Invite.lock.find(signed_invitation.id)
        end

        def signed_invitation!(token)
            Invite.find_signed!(token, purpose: ACCEPTANCE_PURPOSE)
        end

        def validate_token_constraints!(invitation, lock_associations: false)
            invitation_is_available = invitation.acceptance_available? &&
                invitation.accepted_at.nil? &&
                invitation.accepted_user_id.nil? &&
                invitation.cancelled_at.nil?

            unless invitation_is_available
                invalid_invitation!(
                    invitation,
                    :base,
                    I18n.t("lesli_shield.invites.not_acceptable")
                )
            end

            account_relation = relation_for(
                Lesli::Account,
                lock: lock_associations
            )
            account = account_relation.find_by(
                id: invitation.account&.account_id
            )

            unless account&.active?
                invalid_invitation!(
                    invitation,
                    :base,
                    I18n.t("lesli_shield.invites.not_acceptable")
                )
            end

            role_relation = relation_for(
                Lesli::Role,
                lock: lock_associations
            )
            role = role_relation.find_by(id: invitation.role_id)
            valid_role = role&.active? &&
                role.account_id == account.id
            return role if valid_role

            invalid_invitation!(
                invitation,
                :role,
                I18n.t("lesli_shield.invites.role_account_mismatch")
            )
        end

        def validate_invitation_email!(invitation)
            decision = InvitationEmailPolicy.new(
                account: invitation.account.account,
                email: invitation.email
            ).evaluate

            validate_email_decision!(invitation, decision)
        end

        def locked_email_decision(invitation)
            policy = InvitationEmailPolicy.new(
                account: invitation.account.account,
                email: invitation.email
            )
            decision = policy.evaluate

            if decision.recoverable?
                decision.user.lock!
                decision = policy.evaluate
            end

            decision
        end

        def validate_email_decision!(invitation, decision)
            return if decision.allowed?

            invalid_invitation!(
                invitation,
                :email,
                I18n.t("lesli_shield.invites.email_#{decision.status}")
            )
        end

        def build_or_recover_user(invitation, decision, attributes)
            user = decision.recoverable? ? decision.user : Lesli::User.new
            permitted_attributes = attributes.to_h
                .symbolize_keys
                .slice(*USER_ATTRIBUTES)

            user.assign_attributes(permitted_attributes)
            user.email = invitation.email
            user.account = invitation.account.account
            user.skip_confirmation_notification!

            if permitted_attributes[:password].blank?
                user.errors.add(:password, :blank)
                raise ActiveRecord::RecordInvalid, user
            end

            user
        end

        def persist_user!(user)
            user.save!
        end

        def confirm_user!(user)
            confirmed = user.confirm(ensure_valid: true)
            raise ActiveRecord::RecordInvalid, user unless confirmed

            user.update!(
                confirmation_token: nil,
                confirmation_sent_at: nil
            )
        end

        def assign_role!(user, role)
            user.user_roles.find_or_create_by!(role: role)
        end

        def record_audit_event!(operation, invitation, actor:)
            InvitationAudit.record!(
                operation,
                invitation: invitation,
                actor: actor,
                source: self.class
            )
        end

        def enqueue_delivery_after_commit(
            transaction,
            invitation,
            operation:,
            actor:
        )
            acceptance_url = signed_acceptance_url(invitation)

            transaction.after_commit do
                enqueue_invitation_delivery(
                    invitation,
                    acceptance_url,
                    operation: operation,
                    actor: actor
                )
            end
        end

        def enqueue_invitation_delivery(
            invitation,
            acceptance_url,
            operation:,
            actor:
        )
            delivery_job = InvitationDeliveryJob.perform_later(
                invitation.id,
                acceptance_url,
                operation.to_s,
                actor.id
            )

            unless delivery_job.successfully_enqueued?
                enqueue_error = delivery_job.enqueue_error ||
                    RuntimeError.new("Invitation delivery was not enqueued")

                InvitationDeliveryJob.report_enqueue_failure(
                    invitation.id,
                    actor.id,
                    enqueue_error
                )
            end
        rescue StandardError => exception
            InvitationDeliveryJob.report_enqueue_failure(
                invitation.id,
                actor.id,
                exception
            )
        end

        def signed_token_lifetime(invitation)
            remaining_lifetime = if invitation.expires_at.present?
                invitation.expires_at - Time.current
            end

            if remaining_lifetime&.positive?
                return [TOKEN_LIFETIME, remaining_lifetime].min
            end

            invalid_invitation!(
                invitation,
                :base,
                I18n.t("lesli_shield.invites.not_acceptable")
            )
        end

        def relation_for(model, lock:)
            lock ? model.lock : model.all
        end

        def action_mailer_url_options
            options = Rails.application.config.action_mailer.default_url_options
            (options || {}).to_h.symbolize_keys
        end

        def invalid_invitation!(invitation, attribute, message)
            invitation.errors.add(attribute, message)
            raise ActiveRecord::RecordInvalid, invitation
        end
    end
end
