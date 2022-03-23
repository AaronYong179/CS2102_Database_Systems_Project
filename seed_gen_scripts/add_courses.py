import csv
import random

f = open('./sql_files/seed_courses.sql', 'w')

# add_course(course_title, course_description, course_area, duration)

def read_csv(csvfilename):
    rows = []
    with open(csvfilename) as csvfile:
        file_reader = csv.reader(csvfile)
        for row in file_reader:
            rows.append(row)
    return rows

def gen_courses():
    rows = read_csv('./helper_files/courses.csv')
    for row in rows:
        rand_duration = random.randint(1, 3)
        f.write(f"CALL add_course('{row[0]}','{row[1]},'{row[2]}', {rand_duration});\n") 

gen_courses()
f.close()
