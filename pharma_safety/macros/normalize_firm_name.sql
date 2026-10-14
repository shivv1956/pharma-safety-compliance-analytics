{#-
    Reduces a manufacturer / firm name to a comparable key.

      1. Roll up to the parent: when the name says "a subsidiary of X", "a division of X",
         "div of X", "div X" or "d/b/a X", X is used instead of the full name.
      2. Uppercase, drop periods, turn other punctuation into spaces.
      3. Strip legal suffixes and generic company words (INC, LLC, PHARMACEUTICALS, ...) and
         subsidiary-function words (SALES, MARKETING, DEVELOPMENT, EXPORT, ...).
      4. Fall back to the cleaned name when stripping would leave nothing.

    e.g. 'WYETH PHARMACEUTICALS LLC, A SUBSIDIARY OF PFIZER INC.' -> 'PFIZER'
         'PFIZER LABORATORIES DIV PFIZER INC'                    -> 'PFIZER'
         'Pfizer Inc.'                                           -> 'PFIZER'
-#}
{% macro normalize_firm_name(column) -%}
{%- set noise = [
    'INCORPORATED', 'INC', 'LLC', 'LTD', 'LIMITED', 'CORP', 'CORPORATION', 'CO', 'COMPANY',
    'LP', 'LLP', 'PLC', 'GMBH', 'AG', 'SA', 'NV', 'BV', 'SRL', 'PTY',
    'USA', 'US', 'AMERICA', 'AMERICAS', 'INTERNATIONAL', 'GLOBAL', 'THE', 'AND', 'OF',
    'DIV', 'DIVISION', 'HOLDINGS', 'HOLDING', 'GROUP',
    'PHARMACEUTICALS', 'PHARMACEUTICAL', 'PHARMA', 'LABORATORIES', 'LABORATORY', 'LABS', 'LAB',
    'LIFESCIENCES', 'LIFE', 'SCIENCES', 'INDUSTRIES', 'HEALTHCARE', 'HEALTH', 'CARE',
    'THERAPEUTICS', 'BIOTECH', 'BIOSCIENCES', 'BIOPHARMA', 'BIOPHARMACEUTICALS',
    'EXPORT', 'DEVELOPMENT', 'MARKETING', 'SALES', 'OPERATIONS', 'PUERTO RICO'
] -%}
{%- set upper_name = "upper(" ~ column ~ ")" -%}
{%- set parent -%}
coalesce(
    regexp_substr({{ upper_name }}, $$\b(SUBSIDIARY OF|DIVISION OF|DIV|D/B/A|DBA)\b\.? +(OF +)?([^)]+)$$, 1, 1, 'e', 3),
    {{ upper_name }}
)
{%- endset -%}
{%- set cleaned -%}
trim(regexp_replace(regexp_replace(regexp_replace({{ parent }}, $$\.$$, ''), $$[^A-Z0-9 ]$$, ' '), $$\s+$$, ' '))
{%- endset -%}
coalesce(
    nullif(trim(regexp_replace(regexp_replace({{ cleaned }}, $$\b({{ noise | join('|') }})\b$$, ' '), $$\s+$$, ' ')), ''),
    {{ cleaned }}
)
{%- endmacro %}
