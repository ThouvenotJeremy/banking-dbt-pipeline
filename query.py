import duckdb

conn = duckdb.connect('dev.duckdb')

print(conn.execute("    SELECT dt_fct, ptf_id, client_id, asset_id, amount_position, client_categorie    FROM int_ptf_idx    WHERE client_id = 'CLI001'  and dt_fct >='2025-01-31'  ORDER BY dt_fct, asset_id    LIMIT 10").fetchdf())