# frozen_string_literal: true

module LesliShield
    module UserLegalAcceptance
        extend ActiveSupport::Concern

        included do
            attr_accessor :terms_accepted, :legal_acceptance_required

            # Only public signup sets this flag. Existing users, invitations and
            # administrative creation must not receive invented acceptance records.
            validate :validate_registration_terms, on: :create, if: :legal_acceptance_required
            before_create :record_legal_acceptance, if: :legal_acceptance_required
        end

        # Shared by validation and the form: an outdated form needs a new review.
        def current_registration_documents?
            terms_version.present? && privacy_version.present? &&
                terms_version == Lesli.config.shield[:terms_version] &&
                privacy_version == Lesli.config.shield[:privacy_version]
        end

        private

        def validate_registration_terms
            unless ["1", true].include?(terms_accepted)
                errors.add(:base, I18n.t(
                    "overrides.lesli_shield.devise_registrations.message_terms_required",
                    default: :"lesli_shield.devise_registrations.message_terms_required"
                ))
            end

            unless current_registration_documents?
                errors.add(:base, I18n.t("lesli_shield.devise_registrations.message_legal_documents_changed"))
            end
        end

        def record_legal_acceptance
            # Never accept a timestamp or accepted version supplied by the client.
            self.terms_accepted_at = Time.current
            self.terms_version = Lesli.config.shield.fetch(:terms_version)
            self.privacy_version = Lesli.config.shield.fetch(:privacy_version)
        end
    end
end
