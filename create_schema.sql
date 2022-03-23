-- Schema
BEGIN;
DROP TABLE IF EXISTS Employees, Part_Timers, Full_Timers, Instructors, Managers, Administrators, Part_Time_Instructors, Full_Time_Instructors, Areas, Venues, Courses, Offerings, Sessions, Customers, Course_Packages, Credit_Cards, Buys, Cancels, Registers, Redeems, Pay_Slips, Specializes CASCADE;

CREATE TABLE Employees (
  employee_id     SERIAL PRIMARY KEY, 
  employee_name   VARCHAR(500) NOT NULL, 
  contact_num     VARCHAR(100) NOT NULL, 
  email           VARCHAR(100) NOT NULL, 
  address         TEXT NOT NULL,
  date_joined     DATE NOT NULL, 
  date_departed   DATE -- employees cannot be deleted
      CHECK (date_departed IS NULL OR date_departed > date_joined)
);

CREATE TABLE Part_Timers (
  employee_id     INTEGER PRIMARY KEY REFERENCES Employees(employee_id), 
  hourly_rate     NUMERIC NOT NULL CHECK (hourly_rate > 0)
);

CREATE TABLE Full_Timers (
  employee_id     INTEGER PRIMARY KEY REFERENCES Employees(employee_id), 
  monthly_salary  NUMERIC NOT NULL CHECK (monthly_salary > 0)
);

CREATE TABLE Instructors (
  employee_id     INTEGER PRIMARY KEY REFERENCES Employees(employee_id)
);

CREATE TABLE Managers (
  employee_id     INTEGER PRIMARY KEY REFERENCES Full_Timers(employee_id)
);

CREATE TABLE Administrators (
  employee_id     INTEGER PRIMARY KEY REFERENCES Full_Timers(employee_id)
);

CREATE TABLE Part_Time_Instructors (
  employee_id     INTEGER PRIMARY KEY REFERENCES Instructors(employee_id) REFERENCES Part_Timers(employee_id)
);

CREATE TABLE Full_Time_Instructors (
  employee_id     INTEGER PRIMARY KEY REFERENCES Instructors(employee_id) REFERENCES Full_Timers(employee_id)
);

CREATE TABLE Areas (
  area_name       VARCHAR(500) PRIMARY KEY,
  employee_id     INTEGER NOT NULL REFERENCES Managers(employee_id)
);

CREATE TABLE Venues (
  room_id         VARCHAR(100) PRIMARY KEY, 
  floor           INTEGER NOT NULL, 
  room_num        INTEGER NOT NULL,
  max_capacity    INTEGER NOT NULL,
  UNIQUE (floor, room_num)
);

CREATE TABLE Courses (
  course_id       SERIAL PRIMARY KEY, 
  title           VARCHAR(500) UNIQUE NOT NULL, 
  duration        INTEGER NOT NULL, 
  description     TEXT NOT NULL, 
  area_name       VARCHAR(500) NOT NULL REFERENCES Areas(area_name) ON UPDATE CASCADE 
  -- no need to handle delete cascade
);
 
CREATE TABLE Offerings (
  course_id       INTEGER NOT NULL REFERENCES Courses(course_id)
      ON UPDATE CASCADE
      ON DELETE CASCADE,
  launch_date     DATE NOT NULL, 
  fees            NUMERIC NOT NULL, 
  target_reg      INTEGER NOT NULL, 
  reg_deadline    DATE NOT NULL, 
  employee_id     INTEGER NOT NULL REFERENCES Administrators(employee_id), 
  PRIMARY KEY (course_id, launch_date)
  -- an admin cannot be an admin of an Offering that has a launch_date after its departure_date (Employees.date_departed)
);

CREATE TABLE Sessions (
  sess_num        INTEGER NOT NULL,
  sess_date       DATE NOT NULL,
  sess_end_time   TIME NOT NULL,
  sess_start_time TIME NOT NULL, -- 9 to 6, but cannot be 12 to 2
  
  course_id       INTEGER NOT NULL, 
  launch_date     DATE NOT NULL,
  FOREIGN KEY (course_id, launch_date) -- Offering PK
    REFERENCES Offerings(course_id, launch_date)
      ON UPDATE CASCADE
      ON DELETE CASCADE,
  
  room_id         VARCHAR(100) NOT NULL REFERENCES Venues(room_id),
  employee_id     INTEGER NOT NULL REFERENCES Instructors(employee_id),
   
  PRIMARY KEY (course_id, launch_date, sess_num),

  -- check if weekday
  CONSTRAINT check_weekday CHECK (
      EXTRACT(DOW FROM sess_date) IN ('1', '2', '3', '4', '5')
  ),
  -- check start_time
  CONSTRAINT check_start_time CHECK (
      CAST(EXTRACT(HOUR FROM sess_start_time) AS INTEGER) >= 9
      AND (
          CAST(EXTRACT(HOUR FROM sess_start_time) AS INTEGER) <= 17
          OR sess_start_time = TIME '18:00'
      )
  ),
  -- check end_time
  CONSTRAINT check_end_time CHECK (
      CAST(EXTRACT(HOUR FROM sess_end_time) AS INTEGER) >= 9
      AND (
          CAST(EXTRACT(HOUR FROM sess_end_time) AS INTEGER) <= 17
          OR sess_end_time = TIME '18:00'
      )
  ),
  
  -- check if start_time less than end_time
  CONSTRAINT check_start_end_time CHECK (
     sess_start_time < sess_end_time
  )  
);

CREATE TABLE Customers (
  customer_id     SERIAL PRIMARY KEY, 
  customer_name   VARCHAR(500) NOT NULL, 
  address         TEXT NOT NULL, 
  email           VARCHAR(100) NOT NULL, 
  contact_num     VARCHAR(100) NOT NULL
);

CREATE TABLE Course_Packages (
  -- Each course package has a unique package identifier, a package name, the number of free course sessions, a start and end date indicating the duration that the promotional package is available for sale, and the price of the package.
  package_id      SERIAL PRIMARY KEY, 
  package_name    VARCHAR(500) NOT NULL, 
  price           NUMERIC NOT NULL CHECK (price >= 0), 
  max_sess_count  INTEGER NOT NULL 
      CHECK (
          max_sess_count > 0
      ), -- max number of sessions that comes with any package
  start_date      DATE NOT NULL,
  end_date        DATE 
      CHECK (end_date IS NULL OR end_date > start_date)
  -- if null, that means that the package is always available, 
);

CREATE TABLE Credit_Cards (
  credit_card_num CHAR(16) PRIMARY KEY,
  cvv             CHAR(3) NOT NULL,  -- same for CVV
  expiry_date     DATE NOT NULL, -- format MMYY? 
  /* is it possible to set 01-MM-YY whenever the expiry date is entered? */
  customer_id     INTEGER NOT NULL REFERENCES Customers(customer_id)
                      ON UPDATE CASCADE, 
  from_date       TIMESTAMP NOT NULL -- date the credit card is effective from (no transactions required yet)
  
  -- regex check to make sure all 16 characters are integers
  CONSTRAINT proper_credit_card CHECK (credit_card_num ~* '\d{16}'),
  CONSTRAINT proper_cvv CHECK (credit_card_num ~* '\d{3}')
);

CREATE TABLE Buys (
  buy_date        DATE, 
  package_id      INTEGER REFERENCES Course_Packages(package_id)
                      ON UPDATE CASCADE,
  credit_card_num CHAR(16) REFERENCES Credit_Cards(credit_card_num), 
  
  PRIMARY KEY(buy_date, package_id, credit_card_num)
);

CREATE TABLE Cancels (
  -- self attributes
  cancel_date     DATE NOT NULL,
  -- deleted package_credit because it was deemed redundant 
  -- foreign key from Sessions
  course_id       INTEGER NOT NULL, 
  launch_date     DATE NOT NULL,
  sess_num        INTEGER NOT NULL, 
  FOREIGN KEY (course_id, launch_date, sess_num)
    REFERENCES Sessions(course_id, launch_date, sess_num),
  -- foreign key from Customers
  customer_id     INTEGER NOT NULL REFERENCES Customers(customer_id),
  
  PRIMARY KEY (customer_id, course_id, launch_date, sess_num)
);

CREATE TABLE Registers (
  reg_date        DATE NOT NULL,
  -- foreign key from Sessions
  course_id       INTEGER NOT NULL, 
  launch_date     DATE NOT NULL, 
  sess_num        INTEGER NOT NULL,
  FOREIGN KEY (course_id, launch_date, sess_num)
    REFERENCES Sessions(course_id, launch_date, sess_num), 
  -- foreign key from Credit_Cards (can infer Customer from here)
  credit_card_num CHAR(16) NOT NULL
    REFERENCES Credit_Cards(credit_card_num),
  
  PRIMARY KEY (course_id, launch_date, sess_num, reg_date, credit_card_num)
);

CREATE TABLE Redeems (
  redeem_date     DATE NOT NULL, 
  -- foreign key from Sessions
  course_id       INTEGER NOT NULL, 
  launch_date     DATE NOT NULL, 
  sess_num        INTEGER NOT NULL, 
  FOREIGN KEY (course_id, launch_date, sess_num)
    REFERENCES Sessions(course_id, launch_date, sess_num), 
  -- foreign key from Buys
  package_id      INTEGER REFERENCES Course_Packages(package_id),
  buy_date        DATE NOT NULL,
  credit_card_num CHAR(16) NOT NULL, 
  FOREIGN KEY (buy_date, package_id, credit_card_num)
    REFERENCES Buys(buy_date, package_id, credit_card_num),

  PRIMARY KEY (course_id, launch_date, sess_num, buy_date, package_id, credit_card_num, redeem_date)
);

CREATE TABLE Pay_Slips (
  payment_date    DATE NOT NULL,
  num_hours       INTEGER,
  num_days        INTEGER,
  amount          NUMERIC NOT NULL CHECK (amount >= 0),
  employee_id     INTEGER REFERENCES Employees(employee_id)
      ON UPDATE CASCADE
      ON DELETE CASCADE,
  PRIMARY KEY (employee_id, payment_date),
  
  CONSTRAINT pay_slip_type CHECK (
    (num_hours IS NULL AND num_days IS NOT NULL)
    OR (num_days IS NULL AND num_hours IS NOT NULL)
  ),
  CONSTRAINT valid_amount CHECK (
    amount >= 0
  )
);

CREATE TABLE Specializes (
  employee_id     INTEGER REFERENCES Instructors(employee_id),
  area_name       VARCHAR(500) REFERENCES Areas(area_name),
  PRIMARY KEY (employee_id, area_name)
);

COMMIT;
