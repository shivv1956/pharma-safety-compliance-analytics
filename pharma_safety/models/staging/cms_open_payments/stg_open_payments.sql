-- One row per CMS Open Payments general payment to a physician (drug-related).
-- The source uses empty strings for missing values, so text is nullif'd.
-- Up to five products can be linked to one payment; all five names/NDCs are kept
-- and unpivoted in intermediate where drug attribution is needed.

with source as (

    select * from {{ source('cms_open_payments', 'general_payments') }}

),

renamed as (

    select
        program_year::int || '-' || record_id                   as payment_id,
        program_year::int                                       as program_year,
        record_id,
        nullif(trim(change_type), '')                           as change_type,

        nullif(trim(covered_recipient_npi), '')                 as physician_npi,
        nullif(trim(covered_recipient_profile_id), '')          as physician_profile_id,
        nullif(trim(covered_recipient_first_name), '')          as physician_first_name,
        nullif(trim(covered_recipient_middle_name), '')         as physician_middle_name,
        nullif(trim(covered_recipient_last_name), '')           as physician_last_name,
        nullif(trim(covered_recipient_specialty_1), '')         as physician_specialty,
        nullif(trim(recipient_city), '')                        as physician_city,
        nullif(trim(recipient_state), '')                       as physician_state,
        nullif(trim(recipient_zip_code), '')                    as physician_zip_code,
        nullif(trim(recipient_country), '')                     as physician_country,

        nullif(trim(applicable_manufacturer_or_applicable_gpo_making_payment_id), '')
                                                                as manufacturer_id,
        nullif(trim(applicable_manufacturer_or_applicable_gpo_making_payment_name), '')
                                                                as manufacturer_name,
        upper(nullif(trim(applicable_manufacturer_or_applicable_gpo_making_payment_name), ''))
                                                                as manufacturer_name_upper,
        nullif(trim(applicable_manufacturer_or_applicable_gpo_making_payment_state), '')
                                                                as manufacturer_state,
        nullif(trim(applicable_manufacturer_or_applicable_gpo_making_payment_country), '')
                                                                as manufacturer_country,

        try_to_number(total_amount_of_payment_usdollars, 18, 2) as payment_amount_usd,
        try_to_number(number_of_payments_included_in_total_amount)
                                                                as number_of_payments,
        try_to_date(date_of_payment, 'MM/DD/YYYY')              as payment_date,
        try_to_date(payment_publication_date, 'MM/DD/YYYY')     as publication_date,
        nullif(trim(nature_of_payment_or_transfer_of_value), '')
                                                                as payment_nature,
        nullif(trim(form_of_payment_or_transfer_of_value), '')  as payment_form,
        nullif(trim(dispute_status_for_publication), '')        as dispute_status,

        nullif(trim(indicate_drug_or_biological_or_device_or_medical_supply_1), '')
                                                                as product_type_1,
        nullif(trim(product_category_or_therapeutic_area_1), '')
                                                                as product_category_1,
        {% for i in range(1, 6) %}
        nullif(trim(name_of_drug_or_biological_or_device_or_medical_supply_{{ i }}), '')
                                                                as product_name_{{ i }},
        nullif(trim(associated_drug_or_biological_ndc_{{ i }}), '')
                                                                as product_ndc_{{ i }},
        {% endfor %}

        to_timestamp_ntz(_dlt_load_id::number(38,6))                   as _loaded_at

    from source

)

select * from renamed
