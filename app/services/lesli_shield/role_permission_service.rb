# frozen_string_literal: true

module LesliShield
    # Manages a role's selected permission catalog. Saving selections stays
    # intentionally separate from the heavier effective-cache compilation,
    # which is performed on demand by RolePrivilegeDeploymentService.
    class RolePermissionService
        STANDARD_ACTION_ORDER = %w[
            index
            show
            new
            edit
            create
            update
            destroy
        ].freeze

        class Error < StandardError; end

        class UnknownActionsError < Error
            attr_reader :action_ids

            def initialize(action_ids)
                @action_ids = action_ids
                super(
                    I18n.t(
                        "lesli_shield.roles.errors_unknown_actions",
                        action_ids: action_ids.join(", ")
                    )
                )
            end
        end

        def initialize(actor)
            @role_service = RoleService.new(actor)
        end

        def matrix(role_or_id)
            role = manageable_role!(role_or_id)
            records = permission_catalog_for(role)

            build_matrix(records)
        end

        # Validate navigation without building the complete permission matrix.
        # Slugs are the catalog engine names with underscores replaced by hyphens.
        def engine_available?(slug)
            active_catalog.where(
                "REPLACE(parents_lesli_resources.engine, '_', '-') = ?",
                slug
            ).exists?
        end

        # Persists one checkbox change. The role lock keeps simultaneous
        # requests from losing changes made to other permissions.
        def set!(role:, action_id:, enabled:)
            role = manageable_role!(role)

            role.with_lock do
                # Account ownership and permission levels may have changed
                # while this request waited for the lock.
                manageable_role!(role.id)

                action_id = validate_action_id!(action_id)
                timestamp = Time.current
                changed = if enabled
                    enable_action!(role, action_id, timestamp)
                else
                    disable_action!(role, action_id, timestamp)
                end

                next unless changed

                role.update_columns(
                    modified_at: timestamp,
                    updated_at: timestamp
                )
            end

            role
        end

        def duplicate_from!(source_role_or_id, target_role_or_id)
            source = visible_role!(source_role_or_id)
            target = manageable_role!(target_role_or_id)
            selected_ids = active_catalog
                .where(id: source.actions.select(:action_id))
                .order(:id)
                .pluck(:id)

            target.with_lock do
                manageable_role!(target.id)
                timestamp = Time.current

                if synchronize_actions!(target, selected_ids, timestamp)
                    target.update_columns(
                        modified_at: timestamp,
                        updated_at: timestamp
                    )
                end
            end

            target
        end

        # Returns only permissions that currently authorize requests. An
        # inactive role has no effective permissions even if its cache remains.
        def effective_permissions(role_or_id)
            role = visible_role!(role_or_id)
            return [] unless role.active?

            role.privileges
                .where(active: true)
                .order(:controller, :action)
                .pluck(:controller, :action)
                .map do |controller, action|
                    { controller: controller, action: action }
                end
        end

        private

        attr_reader :role_service

        def visible_role!(role_or_id)
            role_service.find!(record_id(role_or_id))
        end

        def manageable_role!(role_or_id)
            role_service.find!(record_id(role_or_id), manageable: true)
        end

        def record_id(role_or_id)
            role_or_id.respond_to?(:id) ? role_or_id.id : role_or_id
        end

        def active_catalog
            Lesli::Resource.actions.joins(:parent)
        end

        def permission_catalog_for(role)
            role_id = ActiveRecord::Base.connection.quote(role.id)
            join = <<~SQL.squish
                LEFT JOIN lesli_shield_role_actions selected_actions
                    ON selected_actions.action_id = lesli_resources.id
                    AND selected_actions.role_id = #{role_id}
            SQL

            active_catalog
                .joins(join)
                .select(
                    "lesli_resources.id AS action_id",
                    "lesli_resources.action AS action_name",
                    "lesli_resources.identifier AS action_identifier",
                    "lesli_resources.label AS action_label",
                    "parents_lesli_resources.id AS resource_id",
                    "parents_lesli_resources.engine AS engine_name",
                    "parents_lesli_resources.identifier AS resource_identifier",
                    "parents_lesli_resources.label AS resource_label",
                    "parents_lesli_resources.route AS resource_route",
                    "selected_actions.id AS role_action_id",
                    "selected_actions.deleted_at AS role_action_deleted_at"
                )
                .to_a
        end

        def build_matrix(records)
            engines = records.group_by { |record| record[:engine_name].to_s }

            engines.map do |engine_name, engine_records|
                build_engine(engine_name, engine_records)
            end.sort_by { |engine| [engine[:label].downcase, engine[:engine]] }
        end

        def build_engine(engine_name, records)
            resources = records.group_by { |record| record[:resource_id] }
                .map { |_resource_id, resource_records| build_resource(resource_records) }
                .sort_by { |resource| [resource[:label].downcase, resource[:route]] }

            {
                engine: engine_name,
                label: engine_label(engine_name),
                resources: resources
            }
        end

        def build_resource(records)
            resource = records.first

            {
                id: resource[:resource_id],
                identifier: resource[:resource_identifier],
                label: readable_label(
                    resource[:resource_label],
                    resource[:resource_identifier],
                    resource[:resource_route]
                ),
                route: resource[:resource_route],
                actions: records
                    .sort_by { |record| action_sort_key(record[:action_name]) }
                    .map { |record| build_action(record) }
            }
        end

        def build_action(record)
            assigned = record[:role_action_id].present? &&
                record[:role_action_deleted_at].nil?
            action_name = record[:action_name].to_s
            standard = STANDARD_ACTION_ORDER.include?(action_name)
            label = readable_label(
                record[:action_label],
                record[:action_identifier],
                action_name
            )

            {
                id: record[:action_id],
                identifier: record[:action_identifier],
                label: label,
                display_label: standard_action_label(action_name, label),
                action: action_name,
                standard: standard,
                assigned: assigned,
                role_action_id: record[:role_action_id]
            }
        end

        def standard_action_label(action_name, fallback)
            return fallback unless STANDARD_ACTION_ORDER.include?(action_name)

            I18n.t(
                "lesli_shield.roles.permissions_standard_actions_#{action_name}",
                default: fallback
            )
        end

        def action_sort_key(action_name)
            action_name = action_name.to_s
            standard_position = STANDARD_ACTION_ORDER.index(action_name)

            return [0, standard_position] if standard_position

            [1, action_name]
        end

        def readable_label(label, identifier, fallback)
            label.presence || identifier.to_s.demodulize.humanize.presence ||
                fallback.to_s.humanize
        end

        def engine_label(engine_name)
            metadata = LesliSystem.engines.values.find do |engine|
                engine[:code].to_s == engine_name
            end

            metadata&.dig(:name).presence || engine_name.to_s.camelize
        end

        def validate_action_id!(action_id)
            normalized_id = Integer(action_id, exception: false)
            valid = normalized_id && active_catalog.exists?(id: normalized_id)

            raise UnknownActionsError, [action_id] unless valid

            normalized_id
        end

        def synchronize_actions!(role, selected_ids, timestamp)
            existing_actions = role.actions.with_deleted
            current_ids = existing_actions
                .where(deleted_at: nil)
                .order(:action_id)
                .pluck(:action_id)
            return false if current_ids == selected_ids

            existing_ids = existing_actions.pluck(:action_id)
            insert_actions!(role, selected_ids - existing_ids, timestamp)
            activate_selected_actions!(existing_actions, selected_ids, timestamp)
            deactivate_unselected_actions!(existing_actions, selected_ids, timestamp)
            true
        end

        def enable_action!(role, action_id, timestamp)
            actions = role.actions.with_deleted
            action = actions.find_by(action_id: action_id)
            return false if action && action.deleted_at.nil?

            if action
                actions.where(id: action.id).update_all(
                    deleted_at: nil,
                    updated_at: timestamp
                )
            else
                Role::Action.create!(
                    role: role,
                    action_id: action_id,
                    created_at: timestamp,
                    updated_at: timestamp
                )
            end

            true
        end

        def disable_action!(role, action_id, timestamp)
            action = role.actions.find_by(action_id: action_id)
            return false unless action

            action.update_columns(
                deleted_at: timestamp,
                updated_at: timestamp
            )
            true
        end

        def insert_actions!(role, action_ids, timestamp)
            records = action_ids.map do |action_id|
                {
                    role_id: role.id,
                    action_id: action_id,
                    created_at: timestamp,
                    updated_at: timestamp
                }
            end

            Role::Action.insert_all!(records) if records.any?
        end

        def activate_selected_actions!(actions, selected_ids, timestamp)
            return if selected_ids.empty?

            actions.where(action_id: selected_ids).update_all(
                deleted_at: nil,
                updated_at: timestamp
            )
        end

        def deactivate_unselected_actions!(actions, selected_ids, timestamp)
            unselected = actions.where(deleted_at: nil)
            unselected = unselected.where.not(action_id: selected_ids) if selected_ids.any?
            unselected.update_all(
                deleted_at: timestamp,
                updated_at: timestamp
            )
        end
    end
end
