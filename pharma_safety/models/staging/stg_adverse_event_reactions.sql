-- One row per reaction listed on a FAERS report (`patient.reaction[]` flattened by dlt).
-- `reaction_term` (MedDRA preferred term) is the text fed to Cortex in the AI layer.

with reactions as (

    select * from {{ source('openfda', 'adverse_events__patient__reaction') }}

),

reports as (

    select adverse_event_report_id, _source_row_id, received_date
    from {{ ref('stg_adverse_events') }}

),

renamed as (

    select
        reactions._dlt_id                                       as adverse_event_reaction_id,
        reports.adverse_event_report_id,
        reports.received_date,
        reactions._dlt_list_idx                                 as reaction_position,

        nullif(trim(reactions.reactionmeddrapt), '')            as reaction_term,
        upper(nullif(trim(reactions.reactionmeddrapt), ''))     as reaction_term_upper,
        reactions.reactionoutcome                               as reaction_outcome_code,
        case reactions.reactionoutcome
            when '1' then 'recovered/resolved'
            when '2' then 'recovering/resolving'
            when '3' then 'not recovered/not resolved'
            when '4' then 'recovered/resolved with sequelae'
            when '5' then 'fatal'
            when '6' then 'unknown'
        end                                                     as reaction_outcome

    from reactions
    inner join reports
        on reactions._dlt_parent_id = reports._source_row_id

)

select * from renamed
