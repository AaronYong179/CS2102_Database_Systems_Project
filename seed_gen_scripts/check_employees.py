def check_sql():
    with open('./sql_files/seed_employees.sql', 'r') as f:
        print(f.read().count("part-time"))
        

check_sql()
