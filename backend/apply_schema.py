import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()

conn = psycopg2.connect(os.environ["DATABASE_URL"])
conn.autocommit = True

with open('src/db/schema.sql', 'r') as f:
    sql = f.read()

with conn.cursor() as cur:
    cur.execute(sql)

print("Schema successfully applied!")
