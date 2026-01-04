import subprocess,psycopg2,time,sys
from prettytable import PrettyTable

DBNAME = "git"
USER = "postgres"
PASSWORD = "postgres"
HOST = "127.0.0.1"
PORT = "5432"

# número de vezes que a query executa
TIMES = 5

def execute_query(query: str):
    conn = psycopg2.connect(f"dbname={DBNAME} user={USER} password={PASSWORD} host={HOST} port={PORT}")
    cur = conn.cursor()
    cur.execute(query)
    res = cur.fetchall()
    conn.close()
    return res

def measure_query(query: str, times=TIMES):
    query_explain = f"EXPLAIN ANALYZE {query}"
    
    exec_times = []
    
    try:
        conn = psycopg2.connect(f"dbname={DBNAME} user={USER} password={PASSWORD} host={HOST} port={PORT}")
        cur = conn.cursor()

        # warm-up
        cur.execute(query_explain)
        
        for i in range(times):
            cur.execute(query_explain)
            plan = cur.fetchall()
            
            exec_time_ms = float(plan[-1][0].split("execution time: ")[1].split(" ms")[0])
            exec_times.append(exec_time_ms / 1000.0)
            print(f"  [EXECUÇÃO {i+1}/{times}]: {exec_time_ms:.3f} ms")

        conn.close()
        
        avg = sum(exec_times) / len(exec_times)
        avg = round(avg, 3)
        return avg
        
    except Exception as e:
        print(f"[ERROR]: {e}")
        sys.exit(1)

def create_q1_table(query_str):
    myTable = PrettyTable(["Nº", "tempo médio (s)"])
    x = 0
    
    while x < 3:
        print(f"\nA executar query1 pela {x+1}ª vez...")
        avg_final = measure_query(query_str)
        myTable.add_row([x+1, avg_final])
        x += 1
        
    print(myTable)
    return myTable

def q2_change_date(query_str: str, new_date: str) -> str:
    STANDARD = "'2024-12-01'"
    formatted_date = f"'{new_date}'"
    
    query_str_res = query_str.replace(STANDARD, formatted_date)
    
    return query_str_res

def create_q2_table(query_str):
    myTable = PrettyTable(["Mês", "Tempo Médio (s)"])
    
    meses = ["2024-12-01", 
             "2024-11-01", 
             "2024-10-01"]
    
    for m in meses:
        print(f"\n--- A testar mês: {m} ---")
        query = q2_change_date(query_str, m)
        avg_final = measure_query(query)
        myTable.add_row([m, avg_final])
        
    print(myTable)
    return myTable

def change_q3_params(query_str: str, start_date: str, end_date: str, interval: str) -> str:
    q = query_str.replace("'2022-01-01'", f"'{start_date}'")
    q = q.replace("'2025-01-01'", f"'{end_date}'")
    q = q.replace("'15 minutes'", f"'{interval}'")
    return q

def run_q3(query_str):
    myTable = PrettyTable(["intervalo", "bin", "tempo médio (s)"])
    scenarios = [
        ("2022-01-01", "2025-01-01", "15 minutes"),
        ("2022-01-01", "2025-01-01", "60 minutes"),
        ("2020-01-01", "2020-06-01", "15 minutes")
    ]
    for start, end, bin_size in scenarios:
        print(f"\n--- a testar Q3: {start} a {end} (bin: {bin_size}) ---")
        q = change_q3_params(query_str, start, end, bin_size)
        avg_final = measure_query(q)
        myTable.add_row([f"{start} a {end}", bin_size, avg_final])
    print("\nRESULTADOS (Q3):")
    print(myTable)

def q4_change_arguments(query_str: str, username: str) -> str:
    STANDARD = "'christopherharmon25'"
    new_username = f"'{username}'" 
    
    query_str_res = query_str.replace(STANDARD,new_username)
    
    return query_str_res

def create_q4_table(query_str):
    myTable = PrettyTable(["arg (username)", "tempo médio (s)"])
    
    args = ["christopherharmon25", 
            "rdavila66", 
            "jenkinsbrandon52"] 
    
    for arg in args:
        print(f"\nA executar query4 com o argumento: {arg}")
        query = q4_change_arguments(query_str, arg)
        avg_final = measure_query(query)
        myTable.add_row([arg, avg_final])
        
    print(myTable)
    return myTable

if __name__ == "__main__":
    
    if len(sys.argv) < 2:
        print("[USAGE]: python3 script_postgres.py <FICHEIRO.SQL>")
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
        print(">>> query 1")
        create_q1_table(query_str)
    
    elif "q2" in filename_lower:
        print(">>> query 2")
        create_q2_table(query_str)
    
    elif "q3" in filename_lower:
        print(">>> query 3")
        run_q3(query_str)

    elif "q4" in filename_lower:
        print(">>> query 4")
        create_q4_table(query_str)
    
    else:
        print(f">>> query para o ficheiro {file_sql} não implementada.")
