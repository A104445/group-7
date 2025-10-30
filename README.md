# GitBench

## Load Data

- Download the dataset (https://storage.googleapis.com/abd_data/gitbench_data.zip) and extract it.

- Install the requirements:
  - With `pip`:
    ```shell
    pip3 install -r db/requirements.txt
    ```

- Create a PostgreSQL database to store the data.

- Load PostgreSQL:
    ```shell
    # replace 'HOST', 'PORT', 'DBNAME', 'USER', and 'PASSWORD' with the
    # respective connection variables.
    python3 db/load.py --data data -H HOST -P PORT -d DBNAME -u USER -p PASSWORD
    ```

- Load DuckDB:
    ```shell
    python3 db/load_duckdb.py --data data
    # database will be stored at 'git.db'
    ```


## Transactional workload (Java 25)

- Install:
```shell
cd transactional
mvn package
```

- Run:
```shell
# replace the connection, warmup, runtime, and client variables with the respective values
java -jar target/transactional-1.0-SNAPSHOT.jar -d jdbc:postgresql://HOST:PORT/DBNAME -U USER -P PASSWORD -W WARMUP -R RUNTIME -c CLIENTS
# E.g.:
java -jar target/transactional-1.0-SNAPSHOT.jar -d jdbc:postgresql://localhost:5432/git -U postgres -P postgres -W 15 -R 180 -c 16
```


## Analytical workloads

The analytical queries can be found in the `analytical` folder.
