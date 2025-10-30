import argparse
from multiprocessing import Pool
import os
import psycopg2
from psycopg2.extensions import connection
from pathlib import Path


# Opens a connection to the database
def createConnection(connStr: str) -> connection:
    return psycopg2.connect(connStr)


# Loads a CSV file into some table
def loadFile(filename: str, tablename, connStr: str):
    print(f"Loading {tablename}")
    conn = createConnection(connStr)
    conn.autocommit = True
    cursor = conn.cursor()

    with open(filename, encoding="utf8") as f:
        cursor.copy_expert(
            f"COPY {tablename} FROM stdin WITH CSV HEADER DELIMITER ',' QUOTE '\"'", f
        )

    conn.close()
    print(f"Loading {tablename} completed")


# Executes a SQL script
def executeScript(filename, connStr: str):
    print(f"Executing {filename}")
    conn = createConnection(connStr)
    cursor = conn.cursor()

    with open(os.path.join(os.path.dirname(__file__), filename)) as f:
        cursor.execute(f.read())

    conn.commit()
    conn.close()


# Runs VACUUM + ANALYZE
def vacuumAnalyze(connStr: str):
    print(f"Running VACUUM ANALYZE")
    conn = createConnection(connStr)
    conn.autocommit = True
    cursor = conn.cursor()
    cursor.execute("VACUUM ANALYZE")
    conn.close()


# Executes the schema.sql script in the provided database and loads each CSV file
def populateDatabase(dataFolder: str, connStr: str):
    executeScript("schema.sql", connStr)

    p = Pool(os.cpu_count())
    jobs = []
    for filename in os.listdir(dataFolder):
        tablename = Path(filename).stem.lower()
        job = p.apply_async(loadFile, (os.path.join(dataFolder, filename), tablename, connStr))
        jobs.append(job)

    [x.get() for x in jobs]

    executeScript("after_populate.sql", connStr)

    vacuumAnalyze(connStr)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-H", "--host", help="PostgreSQL host", default="localhost")
    parser.add_argument("-P", "--port", help="PostgreSQL port", default=5432)
    parser.add_argument("-d", "--database", help="Database name", default="git")
    parser.add_argument("-u", "--user", help="Username", default="postgres")
    parser.add_argument("-p", "--password", help="Password", default="postgres")
    parser.add_argument("--data", help="Directory with the CSV data", default="data")
    args = parser.parse_args()

    connStr = f"postgresql://{args.user}:{args.password}@{args.host}:{args.port}/{args.database}"
    populateDatabase(args.data, connStr)


if __name__ == "__main__":
    main()
