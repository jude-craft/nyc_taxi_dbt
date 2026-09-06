{% macro get_vendor_data(vendor_id) %}
    case {{ vendor_id }}
        when 1 then 'Creative Mobile Technologies'
        when 2 then 'VeriFone Inc.'
        else 'Unknown'
    end
{% endmacro %}