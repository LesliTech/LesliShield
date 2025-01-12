<script setup>

import { onMounted } from "vue"
import { useSessions } from "LesliShield/vue/stores/sessions"


// · implement stores
const storeSessions = useSessions()



// · 
const columns = [{
    field: "id",
    label: "ID"
}, {
    field: "first_name",
    label: "User name"
}, {
    field: "session_source",
    label: "Source"
}, {
    field: "created_at_string",
    label: "Created at"
}, {
    field: "last_used_at_string",
    label: "Last used at"
}, {
    field: "device",
    label: "Device"
}]


// · 
onMounted(() => {
    storeSessions.get()
})

</script>
<template>
    <lesli-application-container>
        <lesli-header title="Sessions"></lesli-header>
        <lesli-toolbar></lesli-toolbar>
        <lesli-table
            :columns="columns"
            :records="storeSessions.sessions.records"
            :pagination="storeSessions.sessions.pagination">
        </lesli-table>
    </lesli-application-container>
</template>
