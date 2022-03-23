from faker import Faker
import random
import datetime
import csv

fake = Faker(['en-US'])
f = open('./sql_files/seed_employees.sql', 'w')
# add_employee(name, address, number, email, salary_amt, salary_type, date_joined, employee_type, *course_areas)

def read_csv(csvfilename):
    rows = []
    with open(csvfilename) as csvfile:
        file_reader = csv.reader(csvfile)
        for row in file_reader:
            rows.append(row)
    return rows

def _gen_areas():
    return list(map(lambda x: x[0], read_csv('./helper_files/areas.csv')))

def _gen_employee(salary_type, employee_type, course_areas):
    START_DATE = datetime.date(1970, 1, 1)
    END_DATE = datetime.date(2021, 4, 1)

    # random name and email
    rand_name = fake.name()
    rand_email = "".join(rand_name.lower().split()) + "@inlook.com"

    # random contact
    rand_num = "".join(["{}".format(random.randint(0, 9)) for num in range(0, 8)])

    # address
    rand_address = " ".join(fake.address().split("\n"))

    # random date start
    rand_days = random.randrange((END_DATE - START_DATE).days)
    rand_date_start = START_DATE + datetime.timedelta(days = rand_days)

    rand_salary_amt = 0

    if salary_type == "full-time":
        rand_salary_amt = round(random.uniform(4000, 6000), 2)
    else:
        rand_salary_amt = round(random.uniform(7, 40), 2)
    
    
    output = f"'{rand_name}', '{rand_address}', '{rand_num}', '{rand_email}', {rand_salary_amt}, '{salary_type}', '{rand_date_start}', '{employee_type}'" + course_areas
    f.write("CALL add_employee(" + output + ");\n")

def format_areas(areas):
    output = ", '{"
    for i, area in enumerate(areas):
        if i == len(areas) - 1:
            output += area
        else:
            output += f'{area}, '
    output += "}'"
    return output

def gen_employee():
    
    areas = _gen_areas()
    get_area = lambda i: format_areas([areas[i],]) if i < 9 else format_areas(list(areas[i:]))
    
    
    for i in range(10):
        # 10 admins
        _gen_employee('full-time', 'administrator', "")

    for i in range(0, 10):
        # 10 managers
        _gen_employee('full-time', 'manager', get_area(i))

    for i in range(0, 20):
        # 4 instructors
        if i % 2 == 0:
            _gen_employee('full-time', 'instructor', get_area(i%10))
        else:
            _gen_employee('part-time', 'instructor', get_area(i%10))

gen_employee()
f.close()








