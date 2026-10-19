Rails.application.routes.draw do
    Lesli::Router.login(self)

    mount Lesli::Engine => "/lesli"
    mount LesliShield::Engine => "/lesli_shield"
end
