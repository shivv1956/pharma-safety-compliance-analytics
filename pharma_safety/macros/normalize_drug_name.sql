{#-
    Reduces a drug name (brand, generic or as-reported) to a comparable key by removing
    strengths, dosage forms, packaging words and salt names:

      'HUMIRA PEN 40 MG/0.8 ML'           -> 'HUMIRA'
      'METFORMIN HYDROCHLORIDE TABLETS'   -> 'METFORMIN'
      'Tivicay PD (dolutegravir) 5mg'     -> 'TIVICAY PD DOLUTEGRAVIR'

    Falls back to the cleaned name when stripping would leave nothing.
-#}
{% macro normalize_drug_name(column) -%}
{%- set noise = [
    'MG', 'MCG', 'UG', 'G', 'ML', 'L', 'IU', 'UNIT', 'UNITS', 'MEQ', 'KG', 'PERCENT',
    'TABLET', 'TABLETS', 'TAB', 'TABS', 'CAPSULE', 'CAPSULES', 'CAP', 'CAPS', 'INJECTION', 'INJ',
    'SOLUTION', 'ORAL', 'SUSPENSION', 'CREAM', 'OINTMENT', 'GEL', 'PATCH', 'SPRAY', 'POWDER',
    'KIT', 'PEN', 'PENS', 'PREFILLED', 'SYRINGE', 'VIAL', 'INJECTABLE', 'FOR', 'AND', 'IN',
    'EXTENDED', 'RELEASE', 'DELAYED', 'ER', 'XR', 'SR', 'DR', 'EC', 'USP', 'NDC',
    'HYDROCHLORIDE', 'HCL', 'SODIUM', 'POTASSIUM', 'SULFATE', 'ACETATE', 'MESYLATE', 'MALEATE',
    'TARTRATE', 'SUCCINATE', 'CITRATE', 'PHOSPHATE', 'BESYLATE', 'FUMARATE', 'CALCIUM'
] -%}
{%- set cleaned -%}
trim(regexp_replace(regexp_replace(regexp_replace(upper({{ column }}), $$[^A-Z0-9 ]$$, ' '), $$\b[0-9]+\b$$, ' '), $$\s+$$, ' '))
{%- endset -%}
coalesce(
    nullif(trim(regexp_replace(regexp_replace({{ cleaned }}, $$\b({{ noise | join('|') }})\b$$, ' '), $$\s+$$, ' ')), ''),
    nullif({{ cleaned }}, ''),
    upper({{ column }})
)
{%- endmacro %}
