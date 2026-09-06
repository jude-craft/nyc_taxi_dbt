{% macro get_trip_duration_minutes(pickup_column, dropoff_column) %}
    date_diff('minute', {{ pickup_column }}, {{ dropoff_column }})
{% endmacro %}