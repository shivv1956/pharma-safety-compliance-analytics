-- One row per drug listed on a FAERS report (`patient.drug[]` flattened by dlt).
-- Drug names are as reported and messy; conforming them happens in int_drug_resolution.

with drugs as (

    select * from {{ source('openfda', 'adverse_events__patient__drug') }}

),

reports as (

    -- join to the deduplicated parent so only the kept report version's drugs survive
    select adverse_event_report_id, _source_row_id, received_date
    from {{ ref('stg_adverse_events') }}

),

renamed as (

    select
        drugs._dlt_id                                           as adverse_event_drug_id,
        reports.adverse_event_report_id,
        reports.received_date,
        drugs._dlt_list_idx                                     as drug_position,

        nullif(trim(drugs.medicinalproduct), '')                as drug_name_reported,
        upper(nullif(trim(drugs.medicinalproduct), ''))         as drug_name_upper,
        nullif(trim(drugs.activesubstance__activesubstancename), '')
                                                                as active_substance_name,

        drugs.drugcharacterization                              as drug_role_code,
        case drugs.drugcharacterization
            when '1' then 'suspect'
            when '2' then 'concomitant'
            when '3' then 'interacting'
        end                                                     as drug_role,

        nullif(trim(drugs.drugindication), '')                  as drug_indication,
        nullif(trim(drugs.drugadministrationroute), '')         as administration_route_code,
        nullif(trim(drugs.drugdosagetext), '')                  as dosage_text,
        nullif(trim(drugs.drugauthorizationnumb), '')           as authorization_number,
        drugs.actiondrug                                        as action_taken_code,

        -- only format 102 (YYYYMMDD) is a full date; the raw value is kept for the rest
        drugs.drugstartdate                                     as drug_start_date_raw,
        iff(drugs.drugstartdateformat = '102', try_to_date(drugs.drugstartdate, 'YYYYMMDD'), null)
                                                                as drug_start_date,
        drugs.drugenddate                                       as drug_end_date_raw,
        iff(drugs.drugenddateformat = '102', try_to_date(drugs.drugenddate, 'YYYYMMDD'), null)
                                                                as drug_end_date

    from drugs
    inner join reports
        on drugs._dlt_parent_id = reports._source_row_id

)

select * from renamed
