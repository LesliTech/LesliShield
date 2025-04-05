module LesliShield
  class ActionsController < ApplicationController
    before_action :set_action, only: %i[ show edit update destroy ]

    # GET /actions
    def index
      @actions = Action.all
    end

    # GET /actions/1
    def show
    end

    # GET /actions/new
    def new
      @action = Action.new
    end

    # GET /actions/1/edit
    def edit
    end

    # POST /actions
    def create
      @action = Action.new(action_params)

      if @action.save
        redirect_to @action, notice: "Action was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /actions/1
    def update
      if @action.update(action_params)
        redirect_to @action, notice: "Action was successfully updated.", status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /actions/1
    def destroy
      @action.destroy!
      redirect_to actions_path, notice: "Action was successfully destroyed.", status: :see_other
    end

    private
      # Use callbacks to share common setup or constraints between actions.
      def set_action
        @action = Action.find(params.expect(:id))
      end

      # Only allow a list of trusted parameters through.
      def action_params
        params.fetch(:action, {})
      end
  end
end
