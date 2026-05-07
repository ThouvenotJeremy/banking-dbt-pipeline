import duckdb

conn = duckdb.connect('dev.duckdb')

print(conn.execute("SELECT * FROM mart_client_exposure").fetchdf())