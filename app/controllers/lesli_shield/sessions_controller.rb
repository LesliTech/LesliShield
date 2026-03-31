module LesliShield
    class SessionsController < ApplicationController
        before_action :set_session, only: %i[ show edit update destroy ]

        # GET /sessions
        def index
            @sessions = respond_with_pagination(UserSessionService.new(current_user, query).index())
            respond_with_lesli(
                :html => @sessions,
                :json => @sessions
            )
        end

        # GET /sessions/1
        def show
        end

        # PATCH/PUT /sessions/1
        def update
        end

        # DELETE /sessions/1
        def destroy
        end

        private

        # Use callbacks to share common setup or constraints between actions.
        def set_session
            @session = Session.find(params.expect(:id))
        end

        # Only allow a list of trusted parameters through.
        def session_params
            params.fetch(:session, {})
        end
    end
end
