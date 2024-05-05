/*
Lesli

Copyright (c) 2023, Lesli Technologies, S. A.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see http://www.gnu.org/licenses/.

Lesli · Ruby on Rails SaaS Development Framework.

Made with ♥ by LesliTech
Building a better future, one line of code at a time.

@contact  hello@lesli.tech
@website  https://www.lesli.tech
@license  GPLv3 http://www.gnu.org/licenses/gpl-3.0.en.html

// · ~·~     ~·~     ~·~     ~·~     ~·~     ~·~     ~·~     ~·~     ~·~
// · 
*/


// · Import Lesli builders
import application from "Lesli/vue/application"
import translation from "Lesli/vue/translation"


// · Import engine translations
import translations from "LesliShield/vue/stores/translations.json"


// · 
import appDashboardShow from "Lesli/vue/shared/dashboards/apps/show.vue"
import appDashboardEdit from "Lesli/vue/shared/dashboards/apps/edit.vue"


// · 
import componentDashboardEngineVersion from "LesliShield/vue/apps/dashboards/components/engine-version.vue"


// · 
const dashboardProps = {
    components: {
        "engine-version": componentDashboardEngineVersion
    }
}


// · Buil Lesli translations
translation(translations)


// · Build a new Lesli application
application("LesliShield", [{
    path: "/",
    component: appDashboardShow, 
    props: dashboardProps
}, {
    path: "/dashboard",
    component: appDashboardShow, 
    props: dashboardProps
}, {
    path: "/dashboards/:id/edit",
    component: appDashboardEdit, 
    props: dashboardProps
}])
