-- One row per FAERS safety report.
-- Flags are '1' when true and missing/'2' otherwise in the source.

with source as (

    select * from {{ source('openfda', 'adverse_events') }}

),

deduped as (

    select *
    from source
    qualify row_number() over (partition by safetyreportid order by _dlt_load_id desc) = 1

),

renamed as (

    select
        safetyreportid                                          as adverse_event_report_id,
        try_to_number(safetyreportversion)                      as report_version,
        _dlt_id                                                 as _source_row_id,

        try_to_date(receivedate, 'YYYYMMDD')                    as received_date,
        try_to_date(receiptdate, 'YYYYMMDD')                    as receipt_date,
        try_to_date(transmissiondate, 'YYYYMMDD')               as transmission_date,

        reporttype                                              as report_type_code,
        nullif(trim(occurcountry), '')                          as occurrence_country,
        nullif(trim(primarysourcecountry), '')                  as primary_source_country,
        nullif(trim(companynumb), '')                           as company_report_number,
        nullif(trim(authoritynumb), '')                         as authority_report_number,
        duplicate = '1'                                         as is_duplicate_report,

        serious = '1'                                           as is_serious,
        coalesce(seriousnessdeath = '1', false)                 as is_death,
        coalesce(seriousnesslifethreatening = '1', false)       as is_life_threatening,
        coalesce(seriousnesshospitalization = '1', false)       as is_hospitalization,
        coalesce(seriousnessdisabling = '1', false)             as is_disabling,
        coalesce(seriousnesscongenitalanomali = '1', false)     as is_congenital_anomaly,
        coalesce(seriousnessother = '1', false)                 as is_other_serious,

        try_to_number(patient__patientonsetage, 18, 2)          as patient_age,
        patient__patientonsetageunit                            as patient_age_unit_code,
        patient__patientagegroup                                as patient_age_group_code,
        case patient__patientsex
            when '1' then 'male'
            when '2' then 'female'
            when '0' then 'unknown'
        end                                                     as patient_sex,
        try_to_number(patient__patientweight, 18, 2)            as patient_weight_kg,
        nullif(trim(patient__summary__narrativeincludeclinical), '')
                                                                as narrative_text,

        primarysource__qualification                            as reporter_qualification_code,
        case primarysource__qualification
            when '1' then 'physician'
            when '2' then 'pharmacist'
            when '3' then 'other health professional'
            when '4' then 'lawyer'
            when '5' then 'consumer or non-health professional'
        end                                                     as reporter_qualification,
        nullif(trim(primarysource__reportercountry), '')        as reporter_country,

        nullif(trim(sender__senderorganization), '')            as sender_organization,
        nullif(trim(receiver__receiverorganization), '')        as receiver_organization,

        to_timestamp_ntz(_dlt_load_id::number(38,6))                   as _loaded_at

    from deduped

)

select * from renamed
