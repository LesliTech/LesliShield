module LesliShield
  class User::RolesController < ApplicationController
    before_action :set_user_role, only: %i[ show edit update destroy ]

    # GET /user/roles
    def index
      @user_roles = User::Role.all
    end

    # GET /user/roles/1
    def show
    end

    # GET /user/roles/new
    def new
      @user_role = User::Role.new
    end

    # GET /user/roles/1/edit
    def edit
    end

    # POST /user/roles
    def create
        #   @user_role = User::Role.new(user_role_params)

        #   if @user_role.save
        #     redirect_to @user_role, notice: "Role was successfully created."
        #   else
        #     render :new, status: :unprocessable_content
        #   end
    end

    # PATCH/PUT /user/roles/1
    def update
    #   if @user_role.update(user_role_params)
    #     redirect_to @user_role, notice: "Role was successfully updated.", status: :see_other
    #   else
    #     render :edit, status: :unprocessable_content
    #   end
    end

    # DELETE /user/roles/1
    def destroy
      @user_role.destroy!
      redirect_to user_roles_path, notice: "Role was successfully destroyed.", status: :see_other
    end

    private
      # Use callbacks to share common setup or constraints between actions.
      def set_user_role
        @user_role = User::Role.find(params.expect(:id))
      end

      # Only allow a list of trusted parameters through.
      def user_role_params
        params.require(:user_role).permit(
            :role_id
        )
      end
  end
end
