-- One row per recall with a rule-based risk category for its free-text reason
-- (see macros/classify_recall_reason.sql).

select
    recall_number,
    recall_reason,
    {{ classify_recall_reason('recall_reason') }} as recall_reason_category
from {{ ref('stg_recalls') }}
