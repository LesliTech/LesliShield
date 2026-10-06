# Dashboard Components

LesliShield registers three shared dashboard components:

| Component | Current presentation |
| --- | --- |
| `calendar` | Calendar widget |
| `chart_bar` | Bar-chart widget |
| `weather` | Weather widget |

The matching partials live in `app/views/lesli_shield/dashboards`. They are starter widgets and do not currently expose authentication or authorization metrics. Replace their demonstration values with account-scoped services before presenting them as security reporting.

Other component partials in that directory are not public dashboard components until their names are added to `LesliShield::Dashboard::COMPONENTS`.

After installing LesliShield for existing accounts, or after registering another component, run:

```shell
bin/rails lesli_dashboard:register
```

Registration creates missing dashboard records without replacing user-customized positions, widths, or configuration. See the [LesliDashboard component contract](/engines/dashboard/about/dashboards) before adding a production widget.
