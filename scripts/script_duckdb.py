import duckdb
import time
import sys
from prettytable import PrettyTable

DB_FILE = "git.db"
TIMES = 5

def measure_query(query: str, times=TIMES):
    exec_times = []
    
    conn = duckdb.connect(DB_FILE)
    
    print(f"  A executar {times} vezes...")
    
    conn.execute(query).fetchall()

    for i in range(times):
        start_time = time.time()
        
        conn.execute(query).fetchall()
        
        end_time = time.time()
        
        exec_time_s = end_time - start_time
        exec_times.append(exec_time_s)
        
        print(f"  [EXECUÇÃO {i+1}/{times}]: {exec_time_s * 1000:.3f} ms")

    conn.close()
    
    avg = sum(exec_times) / len(exec_times)
    return round(avg, 3)

def run_q1(query_str):
    myTable = PrettyTable(["Nº Execução", "tempo médio (s)"])
    x = 0

    while x < 3:
        print(f"\n--- a testar Q1 (Iteração {x+1}) ---")
        avg_final = measure_query(query_str)
        myTable.add_row([x+1, avg_final])
        x += 1
        
    print("\nRESULTADOS (Q1):")
    print(myTable)

def change_q2_date(query_str, new_date):
    return query_str.replace("'2024-12-01'", f"'{new_date}'")

def run_q2(query_str):
    myTable = PrettyTable(["Mês", "Tempo Médio (s)"])
    meses = ["2024-12-01", "2024-11-01", "2024-10-01"]
    
    for m in meses:
        print(f"\n--- a testar mês: {m} ---")
        q = change_q2_date(query_str, m)
        avg = measure_query(q)
        myTable.add_row([m, avg])
        
    print("\nRESULTADOS (Q2):")
    print(myTable)
    
def change_q3_params(query_str: str, start_date: str, end_date: str, interval: str) -> str:
    q = query_str.replace("'2022-01-01'", f"'{start_date}'")
    q = q.replace("'2025-01-01'", f"'{end_date}'")
    q = q.replace("'15 minutes'", f"'{interval}'")
    
    q = q.replace(f"date_bin('{interval}'", f"time_bucket(INTERVAL '{interval}'")
    
    q = q.replace(", '2009-01-01')", ", '2009-01-01'::timestamp)")
    
    return q

def run_q3(query_str):
    myTable = PrettyTable(["Intervalo", "Bin", "Tempo Médio (s)"])
    
    scenarios = [
        ("2022-01-01", "2025-01-01", "15 minutes"),
        ("2022-01-01", "2025-01-01", "60 minutes"),
        ("2020-01-01", "2020-06-01", "15 minutes")
    ]
    
    for start, end, bin_size in scenarios:
        print(f"\n--- a testar Q3: {start} a {end} (bin: {bin_size}) ---")
        
        q = change_q3_params(query_str, start, end, bin_size)
        
        try:
            avg_final = measure_query(q)
            intervalo_str = f"{start} a {end}"
            myTable.add_row([intervalo_str, bin_size, avg_final])
        except Exception as e:
            print(f"[ERROR]: {e}")
        
    print("\nRESULTADOS (Q3):")
    print(myTable)

def change_q4_arguments(query_str: str, username: str) -> str:
    STANDARD = "'christopherharmon25'"
    new_username = f"'{username}'" 
    
    query_str_res = query_str.replace(STANDARD, new_username)
    
    return query_str_res

def run_q4(query_str):
    myTable = PrettyTable(["arg (username)", "tempo médio (s)"])
    
    args = ["christopherharmon25", 
            "rdavila66",
            "jenkinsbrandon52"] 
    
    for arg in args:
        print(f"\n--- a testar argumento: {arg} ---")
        query = change_q4_arguments(query_str, arg)
        avg_final = measure_query(query)
        myTable.add_row([arg, avg_final])
        
    print("\nRESULTADOS (Q4):")
    print(myTable)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("[USAGE]: python3 script_duckdb.py <FICHEIRO.SQL>")
        sys.exit(1)
    
    file_sql = sys.argv[1]
    
    try:
        with open(file_sql, "r") as f:
            query_str = f.read()
    except FileNotFoundError:
        print(f"[ERROR]: ficheiro '{file_sql}' não encontrado.")
        sys.exit(1)

    filename_lower = file_sql.lower()

    if "q1" in filename_lower:
        run_q1(query_str)
    
    elif "q2" in filename_lower:
        run_q2(query_str)
        
    elif "q3" in filename_lower:
        run_q3(query_str)

    elif "q4" in filename_lower:
        run_q4(query_str)
    
    else:
        print(f"query para o ficheiro {file_sql} não implementada.")