module LesliShield
  class SessionsController < ApplicationController
    before_action :set_session, only: %i[ show edit update destroy ]

    # GET /sessions
    def index
        @sessions = UserSessionService.new(current_user, query).index()
        respond_to do |format|
            format.html {}
            format.json { 
                #respond_with_pagination([])
                respond_with_pagination(SessionService.new(current_user, query).index())
            }
        end
    end

    # GET /sessions/1
    def show
    end

    # GET /sessions/new
    def new
      @session = Session.new
    end

    # GET /sessions/1/edit
    def edit
    end

    # POST /sessions
    def create
      @session = Session.new(session_params)

      if @session.save
        redirect_to @session, notice: "Session was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /sessions/1
    def update
      if @session.update(session_params)
        redirect_to @session, notice: "Session was successfully updated.", status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /sessions/1
    def destroy
      @session.destroy!
      redirect_to sessions_path, notice: "Session was successfully destroyed.", status: :see_other
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
