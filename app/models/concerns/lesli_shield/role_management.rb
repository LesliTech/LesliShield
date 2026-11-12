# frozen_string_literal: true

module LesliShield
    module RoleManagement
        extend ActiveSupport::Concern

        SYSTEM_ROLE_NAMES = %w[owner admin guest].freeze
        PROTECTED_ROLE_NAMES = %w[owner].freeze

        def system_role?
            system_role_name.present?
        end

        def protected_role?
            PROTECTED_ROLE_NAMES.include?(system_role_name)
        end

        # A protected role may be inspected, but it cannot be changed through
        # role administration. Equal permission levels are manageable; only a
        # strictly higher role is outside the actor's management boundary.
        def manageable_by?(actor)
            return false if actor.blank? || protected_role?
            return false unless actor.respond_to?(:account_id)
            return false unless actor.respond_to?(:max_level_permission)
            return false if account_id.blank? || actor.account_id != account_id
            return false if permission_level.blank?

            permission_level <= actor.max_level_permission
        end

        def assigned?
            return false unless persisted?

            LesliShield::User::Role.where(role_id: id).exists?
        end

        def deletable_by?(actor)
            manageable_by?(actor) && !system_role? && !assigned?
        end

        private

        # Account initialization creates stable codes such as owner1, admin2,
        # and guest3. Comparing the complete code avoids treating a custom role
        # like "admin247" as a system role by accident.
        def system_role_name
            normalized_code = code.to_s.strip.downcase

            SYSTEM_ROLE_NAMES.find do |system_name|
                normalized_code == "#{system_name}#{id}"
            end
        end
    end
end
