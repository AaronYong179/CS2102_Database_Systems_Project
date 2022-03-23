from faker import Faker
import random as random
import datetime

fake = Faker(['en-GB'])
f = open('./sql_files/seed_customers.sql', 'w')

# add_customer(name, address, number, email, credit_card_num, expiry_date, CVV)

def _gen_customers():

    START_DATE = datetime.date(1970, 1, 1)
    END_DATE = datetime.date(2000, 4, 1)
    rand_days = random.randrange((END_DATE - START_DATE).days)
    
    
    rand_name = fake.name()
    rand_address = " ".join(fake.address().split("\n"))
    rand_email = "".join(rand_name.lower().split()) + "@customers.com"
    rand_num = "".join(["{}".format(random.randint(0, 9)) for num in range(0, 8)])

    rand_cc_num = "".join(["{}".format(random.randint(0, 9)) for num in range(0, 16)])
    rand_cvv = "".join(["{}".format(random.randint(0,9)) for num in range(0,3)])

    rand_expiry_date = (datetime.datetime.now() + datetime.timedelta(days = rand_days)).strftime("%m-%Y")

    output = f"'{rand_name}', '{rand_address}', '{rand_num}', '{rand_email}', '{rand_cc_num}', '{rand_expiry_date}', '{rand_cvv}'"
    f.write("CALL add_customer(" + output + ");\n")

def gen_customers():
    for i in range(10):
        _gen_customers()

gen_customers()
f.close()
