-- One row per physician (CMS profile id), with the attributes from their latest payment.

select
    physician_profile_id                                        as physician_key,
    physician_npi,
    physician_first_name,
    physician_middle_name,
    physician_last_name,
    physician_specialty,
    physician_city,
    physician_state,
    physician_zip_code,
    physician_country
from {{ ref('stg_open_payments') }}
where physician_profile_id is not null
qualify row_number() over (
    partition by physician_profile_id
    order by payment_date desc, program_year desc, record_id desc
) = 1
