{#-
    Buckets free-text FDA recall reasons into a risk category. Rules are evaluated top to
    bottom and the first match wins, so the order encodes clinical priority: a product that
    is both non-sterile and cGMP-deviant is a sterility problem first.
    Rule-based on purpose: auditable and reproducible, which matters for compliance data.
-#}
{% macro classify_recall_reason(column) %}
    case
        when {{ column }} is null then 'unspecified'
        when regexp_like({{ column }}, '.*(sterility|non-sterile|nonsterile|microbial|bacteri|fung|mold|yeast|endotoxin|pyrogen|burkholderia|e\\. ?coli).*', 'i') then 'sterility_microbial'
        when regexp_like({{ column }}, '.*(nitroso|ndma|ndea|benzene|carcinogen|impurit|degradation|toxic|contaminat).*', 'i') then 'chemical_contamination'
        when regexp_like({{ column }}, '.*(foreign|particul|glass|metal|fragment|hair).*', 'i') then 'foreign_matter'
        when regexp_like({{ column }}, '.*(superpotent|subpotent|potency|assay|out of specification|oos).*', 'i') then 'potency'
        when regexp_like({{ column }}, '.*(dissolution|stability|expir|\\bph\\b|storage|temperature|crystalliz|discolor|uniformity|misprint).*', 'i') then 'quality_stability'
        when regexp_like({{ column }}, '.*(label|mislabel|packag|carton|wrong|mix-?up|incorrect|barcode|insert|child.?resistant|\\bcap\\b|container|closure|seal).*', 'i') then 'labeling_packaging'
        when regexp_like({{ column }}, '.*(undeclared|without an approved|unapproved|\\b(nda|anda)\\b).*', 'i') then 'unapproved_or_adulterated'
        when regexp_like({{ column }}, '.*(cgmp|gmp|good manufacturing|processing control|insanitary|inspection).*', 'i') then 'cgmp_deviation'
        else 'other'
    end
{% endmacro %}
