# frozen_string_literal: true

module RoleSecurityTestHelpers
    def insert_account_context(label, manager_level: 100)
        identifier = "#{label}-#{SecureRandom.hex(4)}"
        timestamp = Time.current
        account_id = Lesli::Account.insert_all!([{
            email: "#{identifier}-account@example.com",
            name: "Account #{identifier}",
            status: "active",
            created_at: timestamp,
            updated_at: timestamp
        }]).rows.first.first
        user_id = Lesli::User.insert_all!([{
            account_id: account_id,
            uid: "ROLE-SECURITY-#{identifier.upcase}",
            email: "#{identifier}-user@example.com",
            encrypted_password: "",
            active: true,
            sign_in_count: 0,
            failed_attempts: 0,
            created_at: timestamp,
            updated_at: timestamp
        }]).rows.first.first

        context = {
            account: Lesli::Account.find(account_id),
            user: Lesli::User.find(user_id)
        }
        manager_role = insert_role(
            context,
            name: "Manager #{identifier}",
            permission_level: manager_level
        )
        assign_role(context.fetch(:user), manager_role)
        context.merge(manager_role: manager_role)
    end

    def insert_role(context, name:, permission_level:, system_name: nil)
        timestamp = Time.current
        role_id = Lesli::Role.insert_all!([{
            account_id: context.fetch(:account).id,
            name: name,
            code: "role-#{SecureRandom.hex(6)}",
            permission_level: permission_level,
            active: true,
            created_at: timestamp,
            updated_at: timestamp
        }]).rows.first.first
        role = Lesli::Role.find(role_id)
        role.update_columns(code: "#{system_name}#{role.id}") if system_name
        role.reload
    end

    def assign_role(user, role)
        LesliShield::User::Role.create!(user: user, role: role)
    end

    def grant_privilege(context, controller:, action:)
        LesliShield::Role::Privilege.create!(
            role: context.fetch(:manager_role),
            controller: controller,
            action: action,
            active: true
        )
    end

    def insert_role_action(role, label:)
        timestamp = Time.current
        controller_id = Lesli::Resource.insert_all!([{
            engine: "shield",
            identifier: "RoleSecurity#{SecureRandom.hex(4)}",
            label: label,
            route: "role_security/#{SecureRandom.hex(4)}",
            created_at: timestamp,
            updated_at: timestamp
        }]).rows.first.first
        action_id = Lesli::Resource.insert_all!([{
            action: "index",
            identifier: "index",
            label: "Index",
            parent_id: controller_id,
            created_at: timestamp,
            updated_at: timestamp
        }]).rows.first.first

        LesliShield::Role::Action.create!(role: role, action_id: action_id)
    end

    def with_current_user(user, &block)
        with_controller_methods(current_user: user, &block)
    end

    def with_authorized_request(user, &block)
        with_controller_methods(
            {
                current_user: user,
                authenticate_request: true,
                authorize_request: true,
                log_requests: true
            },
            &block
        )
    end

    # Authentication is stubbed so these controller tests can exercise the
    # real AuthorizationInterface against the user's persisted privileges.
    def with_authenticated_request(user, &block)
        with_controller_methods(
            {
                current_user: user,
                authenticate_request: true,
                log_requests: true,
                log: true
            },
            &block
        )
    end

    def with_controller_methods(overrides)
        controller_singleton = @controller.singleton_class
        original_methods = {}

        overrides.each do |method_name, return_value|
            if controller_singleton.instance_methods(false).include?(method_name)
                original_methods[method_name] = controller_singleton
                    .instance_method(method_name)
            end

            controller_singleton.define_method(method_name) do |*args, **kwargs|
                return_value
            end
        end

        @routes = LesliShield::Engine.routes
        yield
    ensure
        overrides.each_key do |method_name|
            controller_singleton.remove_method(method_name)
            next unless original_methods.key?(method_name)

            controller_singleton.define_method(
                method_name,
                original_methods.fetch(method_name)
            )
        end
    end
end
