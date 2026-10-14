{{
    config(
        materialized='incremental',
        unique_key='payment_id',
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

-- One row per CMS general payment to a physician.
-- A payment can list up to five products; `drug_key` is the primary (first) product so the
-- amount is never split or double-counted. `product_count` shows how many were listed.
-- Manufacturer-level analysis (the core conflict-of-interest view) is not affected.
-- Incremental on `_loaded_at`; re-run with --full-refresh after changing the alias seed.

with payments as (

    select * from {{ ref('stg_open_payments') }}
    {% if is_incremental() %}
    where _loaded_at > (select coalesce(max(_loaded_at), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}

)

select
    payments.payment_id,
    payments.program_year,
    payments.record_id,
    payments.physician_profile_id                               as physician_key,
    manufacturers.manufacturer_key,
    drugs.drug_key,
    to_number(to_char(payments.payment_date, 'YYYYMMDD'))       as date_key,
    payments.payment_date,
    payments.payment_amount_usd,
    payments.number_of_payments,
    payments.payment_nature,
    payments.payment_form,
    payments.product_name_1                                     as primary_product_name,
    (payments.product_name_1 is not null)::int
        + (payments.product_name_2 is not null)::int
        + (payments.product_name_3 is not null)::int
        + (payments.product_name_4 is not null)::int
        + (payments.product_name_5 is not null)::int            as product_count,
    payments.change_type,
    payments._loaded_at
from payments
left join {{ ref('int_manufacturer_resolution') }} as manufacturers
    on manufacturers.source_system = 'payments'
    and manufacturers.raw_name = payments.manufacturer_name
left join {{ ref('int_drug_resolution') }} as drugs
    on drugs.source_system = 'payments'
    and drugs.raw_name = upper(payments.product_name_1)
