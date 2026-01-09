module LesliShield
    class UsersController < ApplicationController
        before_action :set_user, only: %i[ show edit update destroy ]

        # GET /users
        def index
            @users = respond_as_pagination(Lesli::UserService.new(current_user, query).index(params))
        end

        # GET /users/1
        def show
            @activities = @user.result.activities.order(id: :desc).map { |a| {
                id: a[:id],
                title: a[:title].titleize,
                description: a[:description],
                date: Date2.new(a[:created_at]).date_words
            }}
            @sessions = @user.result.sessions
            @user = @user.show
        end

        # GET /users/new
        def new
            @user = User.new
        end

        # GET /users/1/edit
        def edit
        end

        # POST /users
        def create
            @user = User.new(user_params)

            if @user.save
                respond_with_stream(
                    stream_notification_success('User was successfully created.')
                )
            else
                respond_with_stream(
                    stream_notification_danger(@user.errors.full_messages.to_sentence)
                )
            end
        end

        # PATCH/PUT /users/1
        def update

            # check if the user trully exists
            return respond_with_not_found unless @user.found?

            # update the user information
            @user.update(user_params)

            # check saved
            if @user.successful?
                success("User updated successfully!")
                respond_to do |format|
                    format.turbo_stream
                    format.html { redirect_to @user }
                end
            else 
                respond_with_error(@user.errors)
            end
        end

        # DELETE /users/1
        def destroy
            @user.destroy!
            redirect_to users_path, notice: "User was successfully destroyed.", status: :see_other
        end

        private

        # Use callbacks to share common setup or constraints between actions.
        def set_user
            @user = Lesli::UserService.new(current_user).find(params[:id])
        end

        # Only allow a list of trusted parameters through.
        def user_params
            params.require(:user).permit(
                :active,
                :email,
                :alias,
                :title,
                :roles_id,
                :first_name,
                :last_name,
                :telephone
            )
        end
    end
end
