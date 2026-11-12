# frozen_string_literal: true

module LesliShield
    # Owns role administration rules. Every lookup starts from the actor's
    # account and is restricted by the actor's active permission level.
    class RoleService
        DEFAULT_PERMISSION_LEVEL = 10
        DEFAULT_PER_PAGE = 12
        MAX_PER_PAGE = 100

        WRITABLE_ATTRIBUTES = %i[
            name
            description
            active
            path_default
            permission_level
        ].freeze

        SORT_COLUMNS = {
            "id" => "lesli_roles.id",
            "name" => "LOWER(lesli_roles.name)",
            "description" => "LOWER(lesli_roles.description)",
            "active" => "lesli_roles.active",
            "permission_level" => "lesli_roles.permission_level",
            "users" => "users",
            "actions" => "actions"
        }.freeze

        ACTIVE_USERS_SQL = <<~SQL.squish.freeze
            (
                SELECT COUNT(DISTINCT role_users.user_id)
                FROM lesli_shield_user_roles role_users
                INNER JOIN lesli_users users
                    ON users.id = role_users.user_id
                WHERE role_users.role_id = lesli_roles.id
                    AND role_users.deleted_at IS NULL
                    AND users.deleted_at IS NULL
                    AND users.active = TRUE
            )
        SQL

        ACTIVE_ACTIONS_SQL = <<~SQL.squish.freeze
            (
                SELECT COUNT(DISTINCT role_actions.action_id)
                FROM lesli_shield_role_actions role_actions
                WHERE role_actions.role_id = lesli_roles.id
                    AND role_actions.deleted_at IS NULL
            )
        SQL

        class Error < StandardError
            attr_reader :record

            def initialize(message, record: nil)
                @record = record
                super(message)
            end
        end

        class DuplicateNameError < Error; end
        class PermissionLevelError < Error; end
        class ProtectedRoleError < Error; end
        class SystemRoleError < Error; end
        class AssignedUsersError < Error; end

        class ValidationError < Error
            def initialize(record)
                super(record.errors.full_messages.to_sentence, record: record)
            end
        end

        def initialize(actor, query = {})
            @actor = actor
            @query = query || {}
        end

        def list(filters = {})
            roles = visible_roles
            roles = apply_search(roles, filters)
            roles = apply_status(roles, filters)

            roles
                .select(
                    "lesli_roles.*",
                    "#{ACTIVE_USERS_SQL} AS users",
                    "#{ACTIVE_ACTIONS_SQL} AS actions"
                )
                .order(Arel.sql("#{sort_column} #{sort_direction}"))
                .order(id: :asc)
                .page(page)
                .per(per_page)
        end

        def find!(id, manageable: false)
            role = visible_roles.find(id)

            if manageable && !role.manageable_by?(actor)
                raise ActiveRecord::RecordNotFound
            end

            role
        end

        def create!(attributes)
            role = actor.account.roles.new(
                initial_attributes.merge(normalize_attributes(attributes))
            )

            validate_permission_level!(role)
            validate_unique_name!(role)
            save!(role)
        end

        def update!(role_or_id, attributes)
            role = manageable_role!(role_or_id)
            role.assign_attributes(normalize_attributes(attributes))

            validate_permission_level!(role)
            validate_unique_name!(role)
            save!(role)
        end

        def deactivate!(role_or_id)
            role = manageable_role!(role_or_id)
            role.active = false
            save!(role)
        end

        def destroy!(role_or_id)
            role = manageable_role!(role_or_id)

            if role.system_role?
                raise SystemRoleError.new(
                    I18n.t("lesli_shield.roles.errors.system_role"),
                    record: role
                )
            end

            if role.assigned?
                raise AssignedUsersError.new(
                    I18n.t("lesli_shield.roles.errors.assigned_users"),
                    record: role
                )
            end

            role.destroy!
            role
        end

        # Copies configuration and selected active actions, but never user
        # assignments, compiled privileges, or deployment state.
        def duplicate!(role_or_id, attributes = {})
            source = find!(record_id(role_or_id))
            overrides = normalize_attributes(attributes)
            overrides[:name] ||= available_copy_name(source.name)

            Lesli::Role.transaction do
                duplicate = create!(
                    {
                        name: overrides.delete(:name),
                        description: source.description,
                        path_default: source.path_default,
                        permission_level: source.permission_level,
                        active: false
                    }.merge(overrides)
                )

                RolePermissionService
                    .new(actor)
                    .duplicate_from!(source, duplicate)
                duplicate.reload
            end
        end

        private

        attr_reader :actor, :query

        def visible_roles
            actor.account.roles.where(
                permission_level: ..actor.max_level_permission
            )
        end

        def manageable_role!(role_or_id)
            role = visible_roles.find(record_id(role_or_id))

            if role.protected_role?
                raise ProtectedRoleError.new(
                    I18n.t("lesli_shield.roles.errors.protected_role"),
                    record: role
                )
            end

            unless role.manageable_by?(actor)
                raise PermissionLevelError.new(
                    I18n.t(
                        "lesli_shield.roles.errors.permission_level",
                        maximum: actor.max_level_permission
                    ),
                    record: role
                )
            end

            role
        end

        def record_id(role_or_id)
            role_or_id.respond_to?(:id) ? role_or_id.id : role_or_id
        end

        def initial_attributes
            {
                active: true,
                isolated: false,
                path_limited: false,
                path_default: nil,
                permission_level: [
                    DEFAULT_PERMISSION_LEVEL,
                    actor.max_level_permission
                ].min
            }
        end

        def normalize_attributes(attributes)
            normalized = attributes.to_h.symbolize_keys.slice(*WRITABLE_ATTRIBUTES)

            if normalized.key?(:name)
                normalized[:name] = normalized[:name].to_s.squish
            end

            if normalized.key?(:description)
                normalized[:description] = normalized[:description]
                    .to_s
                    .squish
                    .presence
            end

            normalized
        end

        def validate_permission_level!(role)
            return if role.permission_level.blank?
            return if role.permission_level.between?(0, actor.max_level_permission)

            raise PermissionLevelError.new(
                I18n.t(
                    "lesli_shield.roles.errors.permission_level",
                    maximum: actor.max_level_permission
                ),
                record: role
            )
        end

        def validate_unique_name!(role)
            return if role.name.blank?

            duplicates = actor.account.roles
                .where("LOWER(name) = ?", role.name.downcase)
            duplicates = duplicates.where.not(id: role.id) if role.persisted?
            return unless duplicates.exists?

            role.errors.add(
                :name,
                I18n.t("lesli_shield.roles.errors.duplicate_name")
            )
            raise DuplicateNameError.new(
                role.errors.full_messages.to_sentence,
                record: role
            )
        end

        def save!(role)
            role.save!
            role
        rescue ActiveRecord::RecordInvalid
            raise ValidationError, role
        end

        def available_copy_name(source_name)
            base_name = "#{source_name} copy"
            candidate = base_name
            suffix = 2

            while name_exists?(candidate)
                candidate = "#{base_name} #{suffix}"
                suffix += 1
            end

            candidate
        end

        def name_exists?(name)
            actor.account.roles.where("LOWER(name) = ?", name.downcase).exists?
        end

        def apply_search(roles, filters)
            search = query[:search].presence || filter_value(filters, :search).presence
            return roles unless search

            pattern = "%#{ActiveRecord::Base.sanitize_sql_like(search.downcase)}%"
            roles.where(
                "LOWER(lesli_roles.name) LIKE :pattern " \
                "OR LOWER(COALESCE(lesli_roles.description, '')) LIKE :pattern",
                pattern: pattern
            )
        end

        def apply_status(roles, filters)
            case filter_value(filters, :status).to_s
            when "active"
                roles.where(active: true)
            when "inactive"
                roles.where(active: false)
            else
                roles
            end
        end

        def filter_value(filters, key)
            filters&.[](key) || filters&.[](key.to_s)
        end

        def sort_column
            SORT_COLUMNS.fetch(query.dig(:order, :by).to_s, SORT_COLUMNS.fetch("id"))
        end

        def sort_direction
            query.dig(:order, :dir).to_s.casecmp?("asc") ? "ASC" : "DESC"
        end

        def page
            requested = query.dig(:pagination, :page).to_i
            requested.positive? ? requested : 1
        end

        def per_page
            requested = query.dig(:pagination, :perPage).to_i
            return DEFAULT_PER_PAGE unless requested.positive?

            [requested, MAX_PER_PAGE].min
        end
    end
end
