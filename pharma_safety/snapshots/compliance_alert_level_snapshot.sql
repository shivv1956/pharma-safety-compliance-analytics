{% snapshot compliance_alert_level_snapshot %}
{{
    config(
        target_schema='snapshots',
        unique_key='manufacturer_key',
        strategy='check',
        check_cols=['alert_level', 'signals_met']
    )
}}

-- History of each manufacturer's alert level, so the agent and dashboard can show when a
-- manufacturer escalated from 'watch' to 'critical' (or dropped off).
select manufacturer_key, alert_level, signals_met
from {{ ref('mart_compliance_risk_signals') }}

{% endsnapshot %}
