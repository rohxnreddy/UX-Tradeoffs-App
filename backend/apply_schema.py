import os
import asyncio
import asyncpg

# Manually parse .env to avoid ModuleNotFoundError on different Python instances
env_path = os.path.join("src", ".env")
if os.path.exists(env_path):
    with open(env_path) as f:
        for line in f:
            if line.strip() and not line.startswith("#"):
                key, val = line.strip().split("=", 1)
                os.environ[key] = val

async def main():
    conn = await asyncpg.connect(os.environ["DATABASE_URL"])
    try:
        # Terminate other active connections to prevent DROP TABLE from hanging
        db_name = await conn.fetchval("SELECT current_database()")
        if db_name:
            await conn.execute(f"""
                SELECT pg_terminate_backend(pid)
                FROM pg_stat_activity
                WHERE datname = '{db_name}' AND pid <> pg_backend_pid()
            """)

        with open('src/db/schema.sql', 'r') as f:
            sql = f.read()

        # Safely clear old tables before applying the new schema
        await conn.execute("DROP TABLE IF EXISTS iqa_results, pesq_results, peaq_results, vmaf_results, device_sessions, sessions, users CASCADE;")
        await conn.execute(sql)
        print("DB Schema successfully applied!")
    except Exception as e:
        print(f"Error applying schema: {e}")
    finally:
        await conn.close()

if __name__ == "__main__":
    asyncio.run(main())
