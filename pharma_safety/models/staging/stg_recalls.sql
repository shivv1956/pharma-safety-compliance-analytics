-- One row per drug recall (openFDA enforcement report).
-- `recalling_firm` is messy and feeds int_manufacturer_resolution;
-- `reason_for_recall` is free text classified by Cortex in the AI layer.

with source as (

    select * from {{ source('openfda', 'recalls') }}

),

deduped as (

    select *
    from source
    -- recalls FDA has not classified yet carry no recall number ('N/A' or blank), so they
    -- cannot be keyed or classified; they appear once FDA assigns a number and class
    where nullif(trim(recall_number), '') is not null
      and recall_number != 'N/A'
    qualify row_number() over (partition by recall_number order by _dlt_load_id desc) = 1

),

renamed as (

    select
        recall_number,
        _dlt_id                                                 as _source_row_id,
        nullif(trim(event_id), '')                              as recall_event_id,

        nullif(trim(recalling_firm), '')                        as recalling_firm,
        upper(nullif(trim(recalling_firm), ''))                 as recalling_firm_upper,
        nullif(trim(city), '')                                  as firm_city,
        nullif(trim(state), '')                                 as firm_state,
        nullif(trim(country), '')                               as firm_country,

        nullif(trim(product_description), '')                   as product_description,
        nullif(trim(product_type), '')                          as product_type,
        nullif(trim(product_quantity), '')                      as product_quantity,

        nullif(trim(reason_for_recall), '')                     as recall_reason,
        classification                                          as recall_classification,
        case classification
            when 'Class I'   then 1
            when 'Class II'  then 2
            when 'Class III' then 3
        end                                                     as recall_severity_rank,
        classification = 'Class I'                              as is_class_i,

        nullif(trim(status), '')                                as recall_status,
        nullif(trim(voluntary_mandated), '')                    as voluntary_or_mandated,
        nullif(trim(initial_firm_notification), '')             as initial_firm_notification,
        nullif(trim(distribution_pattern), '')                  as distribution_pattern,

        try_to_date(recall_initiation_date, 'YYYYMMDD')         as recall_initiation_date,
        try_to_date(center_classification_date, 'YYYYMMDD')     as classification_date,
        try_to_date(report_date, 'YYYYMMDD')                    as report_date,
        try_to_date(termination_date, 'YYYYMMDD')               as termination_date,

        to_timestamp_ntz(_dlt_load_id::number(38,6))                   as _loaded_at

    from deduped

)

select * from renamed
