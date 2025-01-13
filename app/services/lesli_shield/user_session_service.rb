
module LesliShield
    class UserSessionService < ApplicationService
        def index
            Lesli::User::Session
            .joins(:user)
            .select(
                :id,
                :user_id,
                :first_name,
                :session_source,
                Date2.new.date_time.db_column("created_at", "lesli_user_sessions"),
                Date2.new.date_time.db_column("last_used_at"),
                Date2.new.date_time.db_column("expiration_at"),
                "CONCAT_WS(' ', agent_platform, agent_os, '/', agent_browser, agent_version) as device"
            )
            .page(query[:pagination][:page])
            .per(query[:pagination][:perPage])
            .order(updated_at: :desc)
        end
    end
end
