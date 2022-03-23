### CALL public.add_course_offering(
##	<_course_id integer>, 
##	<fees numeric>, 
##	<launch_date date>, 
##	<reg_deadline date>, 
##	<admin_id integer>, 
##	<sess_inputs sess_input[]>, 
##	<target_reg integer>
##)

import random
import datetime


def gen_course_offering():
    START_DATE = datetime.date(2020, 1, 1)
    END_DATE = datetime.date(2030, 1, 1)
    
    f = open("./sql_files/seed_offerings.sql", 'w')
    
    for i in range(1,11):
        # loop through course_ids

        rand_fees = round(random.uniform(10,30), 2)

        while True:
            rand_days = random.randrange((END_DATE - START_DATE).days)
            rand_sess_date = START_DATE + datetime.timedelta(days = rand_days)
            if rand_sess_date.isoweekday() in range(1, 6):
                break

        reg_deadline = rand_sess_date - datetime.timedelta(days=10)
        launch_date = rand_sess_date - datetime.timedelta(days=31)
        ADMIN_ID = 1

        sess_start_time = '09:00:00'
        room_id = '#01-01'
        target_reg = 2
        f.write(f"CALL add_course_offering({i}, {rand_fees}, '{launch_date}', '{reg_deadline}', {ADMIN_ID}, ARRAY[('{rand_sess_date}','{sess_start_time}', '{room_id}')]::SESS_INPUT[], {target_reg});\n")
    f.close()        
        

