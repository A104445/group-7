import argparse
import duckdb
import os
from pathlib import Path


# Loads a CSV file into some table
def loadFile(filename: str, tablename, conn: duckdb.DuckDBPyConnection):
    print(f"Loading {tablename}")
    conn.execute(f"CREATE TABLE {tablename} AS SELECT * FROM read_csv('{filename}')")
    print(f"Loading {tablename} completed")


# Loads each CSV file
def populateDatabase(dataFolder: str):
    # remove the previous database, if exists
    try:
        os.remove("git.db")
    except OSError:
        pass

    conn = duckdb.connect("git.db")

    for filename in os.listdir(dataFolder):
        tablename = Path(filename).stem.lower()
        loadFile(os.path.join(dataFolder, filename), tablename, conn)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", help="Directory with the CSV data", default="data")
    args = parser.parse_args()

    populateDatabase(args.data)


if __name__ == "__main__":
    main()
