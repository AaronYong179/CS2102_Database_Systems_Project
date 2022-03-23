-- No two sessions for the same course offering
-- can be conducted on the same day and at the same time.
CREATE OR REPLACE FUNCTION check_unique_session() RETURNS TRIGGER AS $$
DECLARE
    curs CURSOR FOR (SELECT * FROM Sessions);
    r RECORD;
BEGIN
    OPEN curs;
    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT FOUND;
        IF (NEW.sess_date = sess_date 
            AND NEW.course_id = course_id
            AND (NEW.sess_start_time, NEW.sess_end_time) 
                OVERLAPS (r.sess_start_time, r.sess_end_time)) THEN
            RAISE EXCEPTION 'Session offering already conducted at the same day/time.';
        END IF;
    END LOOP;
    CLOSE curs;
    RETURN NEW;

END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER check_unique_session_trigger
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION check_unique_session();


-- Each room can be used to conduct at most one course session at any time.
CREATE OR REPLACE FUNCTION check_room_occupied() RETURNS TRIGGER AS $$
DECLARE
    curs CURSOR FOR (SELECT * FROM Sessions);
    r RECORD;
BEGIN
    OPEN curs;
    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT FOUND;
        IF (NEW.room_id = r.room_id
            AND (NEW.sess_date = r.sess_date)
            AND (NEW.sess_start_time, NEW.sess_end_time) 
                OVERLAPS (r.sess_start_time, r.sess_end_time)) THEN
            RAISE EXCEPTION 'Room already occupied';
        END IF;
    END LOOP;
    CLOSE curs;
    RETURN NEW;

END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER check_room_occupied_trigger
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION check_room_occupied();

-- Each instructor can teach at most one course session at any hour.
CREATE OR REPLACE FUNCTION check_unique_instructor() RETURNS TRIGGER AS $$
DECLARE
    curs CURSOR FOR (SELECT * FROM SESSIONS);
    r RECORD;
BEGIN
    OPEN curs;
    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT FOUND;
        IF (NEW.employee_id = r.employee_id 
            AND NEW.sess_date = r.sess_date 
            AND (NEW.sess_start_time, NEW.sess_end_time) 
                OVERLAPS (r.sess_start_time, r.sess_end_time)) THEN
            RAISE EXCEPTION 'Instructor already teaching another session';
        END IF;
    END LOOP;
    RETURN NEW;

END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER check_unique_instructor_trigger
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION check_unique_instructor();


-- Each instructor must not be assigned to teach two consecutive sessions
CREATE OR REPLACE FUNCTION check_not_consecutive() RETURNS TRIGGER AS $$
DECLARE
    _sess_date DATE;
    _sess_start TIME;
    _sess_end TIME;
    _instructor INTEGER;
BEGIN
    -- identify the row that will be added at the end using NEW/OLD
    _sess_date := COALESCE(NEW.sess_date, OLD.sess_date);
    _sess_start := COALESCE(NEW.sess_start_time, OLD.sess_start_time);
    _sess_end := COALESCE(NEW.sess_end_time, OLD.sess_end_time);
    _instructor := COALESCE(NEW.employee_id, OLD.employee_id);

    IF EXISTS (SELECT 1 FROM Sessions S
        WHERE S.sess_date = _sess_date
        AND S.employee_id = _instructor
        AND (_sess_start - INTERVAL '1 hour', _sess_end + INTERVAL '1 hour')
            OVERLAPS (S.sess_start_time, S.sess_end_time)
        ) THEN
        RAISE EXCEPTION 'Instructor (%) cannot be assigned to teach this session (%, %, %)', _instructor, 
            _sess_date, _sess_start_time, _sess_end_time;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER check_not_consecutive_trigger
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION check_not_consecutive();

-- Each instructor must specialize in the same area as the session
CREATE OR REPLACE FUNCTION instructor_specialization() RETURNS TRIGGER AS $$
DECLARE
    related_area VARCHAR(500);
BEGIN
    SELECT area_name INTO related_area FROM Courses c WHERE c.course_id = NEW.course_id;
    IF related_area IS NOT NULL AND EXISTS (SELECT 1 FROM Specializes S
        WHERE S.employee_id = NEW.employee_id AND S.area_name = related_area)THEN
        RAISE EXCEPTION 'Instructor not specialized in the given area_name (%)', related_area;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER instructor_specialization_trigger
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION instructor_specialization();

Offerings
-- an admin cannot be an admin of an Offering that has a launch_date after its departure_date (Employees.date_departed).
-- When an offering is inserted/updated with an admin_id, check that the admin is valid
-- When an employee is inserted/updated with date_departed value and they are an admin, any offerings they are
--     adminstrating will be have a launch_date before their departure
CREATE OR REPLACE FUNCTION check_valid_admin_on_offerings()
DECLARE
    _launch_date DATE;
    _date_departed DATE;
RETURNS TRIGGER AS $$
    SELECT date_departed INTO _date_departed FROM Employees E WHERE E.employee_id = NEW.employee_id; 
    
    CASE TG_OP
        WHEN 'INSERT' THEN
            IF _date_departed IS NOT NULL AND NEW.launch_date > _date_departed THEN
                RAISE EXCEPTION 'The offering\'s launch date (%) cannot be after the admin\'s (%) date departed', 
                    NEW.launch_date, NEW.employee_id;
            END IF;
            
            RETURN NEW;
        WHEN 'UPDATE' THEN
            IF _date_departed IS NOT NULL AND COALESCE(NEW.launch_date, OLD.launch_date) > _date_departed THEN
                RAISE EXCEPTION 'The offering\'s launch date (%) cannot be after the admin\'s (%) date departed',
                    COALESCE(NEW.launch_date, OLD.launch_date), NEW.employee_id;
            END IF;
            
            RETURN NEW;
    END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER check_valid_admin_on_offerings
BEFORE INSERT OR UPDATE ON Offerings
WHEN(NEW.employee_id IS NOT NULL)
FOR EACH ROW EXECUTE FUNCTION check_valid_admin_on_offerings();

CREATE OR REPLACE FUNCTION check_valid_admin_on_employees()
RETURNS TRIGGER
AS $$
BEGIN
    IF EXISTS(SELECT 1 FROM Offerings O
        WHERE O.employee_id = COALESCE(NEW.employee_id, OLD.employee_id)
        AND O.launch_date > NEW.date_departed) THEN
        RAISE EXCEPTION 'This employee is an adminstrator for some course offering that has a launch date after their departure';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER check_valid_admin_on_employees
BEFORE INSERT OR UPDATE ON Employees
WHEN(NEW.date_departed IS NOT NULL)
FOR EACH ROW EXECUTE FUNCTION check_valid_admin_on_employees();
  
-- each offering must have at least 1 session
-- when an offering is added, it must be accompanied by at least 1 session
-- when a session is deleted, its related offering must still have at least 1 session
CREATE OR REPLACE FUNCTION check_at_least_one_session_on_offerings()
RETURNS TRIGGER AS $$
    IF EXISTS (SELECT 1
        FROM Offerings_With_Metadata
        WHERE start_date IS NULL
        OR end_date IS NULL
        OR sum_capacity IS NULL) THEN
        RAISE EXCEPION 'Each offering must have 1 session';
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE CONSTRAINT TRIGGER check_at_least_one_session_on_offerings
AFTER INSERT ON Offerings
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_at_least_one_session_on_offerings();

CREATE OR REPLACE FUNCTION check_at_least_one_session_on_sessions()
RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT COUNT(*)
        FROM Sessions
        WHERE course_id = OLD.course_id
            AND launch_date = OLD.launch_date
            AND sess_num = OLD.sess_num) = 1 THEN
        RAISE EXCEPION 'Each offering must have 1 session';
        RETURN NULL;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER at_least_one_session_trigger_on_sessions
BEFORE DELETE ON Sessions
FOR EACH ROW EXECUTION FUNCTION check_at_least_one_session_on_sessions();

-- part time instructors cannot work for more than 30 hours per month
CREATE OR REPLACE FUNCTION _instructor_hrs_by_month()
RETURNS TABLE
(mth_yr DATE, employee_id INTEGER, num_hours INTEGER)
AS $$
BEGIN
    RETURN QUERY
    SELECT mth_yr, employee_id, SUM(C.duration)::INTEGER
    FROM Sessions S
        NATURAL JOIN Courses C
    GROUP BY MAKE_DATE(EXTRACT(YEAR FROM S.sess_date)::INTEGER,
        EXTRACT(MONTH FROM S.sess_month)::INTEGER,
        1) AS mth_yr, employee_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_pt_instructor_does_not_exceed_30hrs()
RETURNS TRIGGER $$
BEGIN
    IF EXISTS(SELECT 1 FROM Full_Timers ft WHERE ft.employee_id = NEW.employee_id) THEN
        -- Since this is an after trigger, this return value is meaningless
        RETURN NEW;
    ELSIF EXISTS(SELECT 1 FROM Part_Timers pt WHERE pt.employee_id = NEW.employee_id)
        AND EXISTS(SELECT 1 FROM _instructor_hrs_by_month() WHERE num_hours > 30) THEN
        ROLLBACK;
        RAISE EXCEPTION 'The instructor given is a part-timer and has exceeded 30 hours';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER check_pt_instructor_does_not_exceed_30hrs
AFTER INSERT OR UPDATE ON Sessions
WHEN (NEW.employee_id IS NOT NULL)
FOR EACH ROW EXECUTION FUNCTION check_pt_instructor_does_not_exceed_30hrs();
Employees
changed all triggers to AFTER
fixed all syntax errors, havent checked for run-time errors yet

-- Each employee must be a part timer or full timer
CREATE OR REPLACE FUNCTION check_employee_ft_or_pt()
RETURNS TRIGGER AS $$
DECLARE
    emp_id INTEGER;
BEGIN
    emp_id := (CASE TG_OP
        WHEN 'INSERT' THEN NEW.employee_id
        WHEN 'UPDATE' THEN NEW.employee_id
        WHEN 'DELETE' THEN OLD.employee_id
    END);
    
	IF 1 <> (
        SELECT COUNT(*) FROM (
            SELECT * FROM Full_Timers FT WHERE emp_id = FT.employee_id
			UNION
            SELECT * FROM Part_Timers PT WHERE emp_id = PT.employee_id) AS _
    ) THEN
        RAISE EXCEPTION 'Employee must be either a part-timer or a full-timer';
    ELSE
        RETURN CASE TG_OP
            WHEN 'INSERT' OR 'UPDATE' THEN NEW
            WHEN 'DELETE' THEN OLD
        END;
	END IF;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER check_employee_ft_or_pt_trigger
AFTER INSERT ON Employees
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_employee_ft_or_pt();
  
-- Each employee must be admin, manager, instructor
-- fixed syntax error with subquery alias
CREATE OR REPLACE FUNCTION check_employee_type()
RETURNS TRIGGER AS $$
BEGIN
	IF 1 <> (SELECT COUNT(*) FROM (
		SELECT * FROM Administrators A WHERE NEW.employee_id = A.employee_id
		UNION
		SELECT * FROM Managers M WHERE NEW.employee_id = M.employee_id
		UNION
		SELECT * FROM Instructors I WHERE NEW.employee_id = I.employee_id) AS _
	) THEN 
		RAISE EXCEPTION 'Each employee must be either an administrator, manager, or instructor.';
	END IF;
    RETURN CASE TG_OP
            WHEN 'INSERT' OR 'UPDATE' THEN NEW
            WHEN 'DELETE' THEN OLD
        END;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER check_employee_type_in_employees_trigger
AFTER INSERT OR UPDATE OR DELETE ON Employees
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_employee_type();
  
CREATE CONSTRAINT TRIGGER check_employee_type_in_administrators_trigger
AFTER INSERT OR UPDATE OR DELETE ON Administrators
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_employee_type();
  
CREATE CONSTRAINT TRIGGER check_employee_type_in_managers_trigger
AFTER INSERT OR UPDATE OR DELETE ON Managers
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_employee_type();
  
CREATE CONSTRAINT TRIGGER check_employee_type_in_instructors_trigger
AFTER INSERT OR UPDATE OR DELETE ON Instructors
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_employee_type();
  
  -- Each part timer must be a part-time instructor
CREATE OR REPLACE FUNCTION check_part_timer_type()
RETURNS TRIGGER AS $$
DECLARE
    emp_id INTEGER;
BEGIN
    emp_id := (CASE TG_OP
        WHEN 'INSERT' THEN NEW.employee_id
        WHEN 'UPDATE' THEN NEW.employee_id
        WHEN 'DELETE' THEN OLD.employee_id
    END);
    
    -- Can think of natural join as intersection between Part_Timers and Part_Time_Instructors
    IF NOT EXISTS (
        SELECT *
        FROM (Part_Timers NATURAL JOIN Part_Time_Instructors) X
        WHERE emp_id = X.employee_id
    ) THEN
        RAISE EXCEPTION 'Each part-timer must be a part-time instructor.';
    END IF;
    RETURN CASE TG_OP
            WHEN 'INSERT' OR 'UPDATE' THEN NEW
            WHEN 'DELETE' THEN OLD
        END;
END;
$$ LANGUAGE plpgsql;

-- TODO: this update quite weird
CREATE CONSTRAINT TRIGGER check_part_timer_type_in_part_timers_trigger
AFTER INSERT OR UPDATE OR DELETE ON Part_Timers
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_part_timer_type();

-- TODO: this update quite weird
CREATE CONSTRAINT TRIGGER check_part_timer_type_in_part_time_instructors_trigger
AFTER INSERT OR UPDATE OR DELETE ON Part_Time_Instructors
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_part_timer_type();
  
-- Each full timer must be a manager, administrator, or full_time_instructor
CREATE OR REPLACE FUNCTION check_full_timer_type()
RETURNS TRIGGER AS $$
DECLARE
    emp_id INTEGER;
BEGIN
    emp_id := (CASE TG_OP
        WHEN 'INSERT' THEN NEW.employee_id
        WHEN 'UPDATE' THEN NEW.employee_id
        WHEN 'DELETE' THEN OLD.employee_id
    END);
    
    IF 1 <> (
        SELECT COUNT(*) FROM (
            SELECT * FROM Managers M WHERE emp_id = M.employee_id
			UNION
            SELECT * FROM Administrators A WHERE emp_id = A.employee_id 
			UNION
            SELECT * FROM Full_Time_Instructors F WHERE emp_id = F.employee_id) AS _
    ) THEN
        RAISE EXCEPTION 'Each full-timer must be a manager, administrator, or full_time_instructor';
    END IF;
    RETURN CASE TG_OP
            WHEN 'INSERT' OR 'UPDATE' THEN NEW
            WHEN 'DELETE' THEN OLD
        END;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER check_full_timer_type_in_full_timers_trigger
AFTER INSERT OR UPDATE OR DELETE ON Full_Timers
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_full_timer_type();

CREATE CONSTRAINT TRIGGER check_full_timer_type_in_managers_trigger
AFTER INSERT OR UPDATE OR DELETE ON Managers
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_full_timer_type();

CREATE CONSTRAINT TRIGGER check_full_timer_type_in_administrators_trigger
AFTER INSERT OR UPDATE OR DELETE ON Administrators
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_full_timer_type();

CREATE CONSTRAINT TRIGGER check_full_timer_type_in_full_time_instructors_trigger
AFTER INSERT OR UPDATE OR DELETE ON Full_Time_Instructors
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_full_timer_type();


-- Each instructor must be a part-time instructor or a full-time instructor
CREATE OR REPLACE FUNCTION check_instructor_type()
RETURNS TRIGGER AS $$
DECLARE
    emp_id INTEGER;
BEGIN
    emp_id := (CASE TG_OP
        WHEN 'INSERT' THEN NEW.employee_id
        WHEN 'UPDATE' THEN NEW.employee_id
        WHEN 'DELETE' THEN OLD.employee_id
    END);
    
    IF 1 <> (
        SELECT COUNT(*) FROM (
            SELECT * FROM Part_Time_Instructors P WHERE NEW.employee_id = P.employee_id
			UNION
			SELECT * FROM Full_Time_Instructors F WHERE NEW.employee_id = F.employee_id
		) AS _
    ) THEN
        RAISE EXCEPTION 'Each instructor must be a part-time instructor or a full-time instructor';
    END IF;
    RETURN CASE TG_OP
            WHEN 'INSERT' OR 'UPDATE' THEN NEW
            WHEN 'DELETE' THEN OLD
        END;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER check_instructor_type_in_full_time_instructors_trigger
AFTER INSERT OR UPDATE OR DELETE ON Full_Time_Instructors
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_instructor_type();

CREATE CONSTRAINT TRIGGER check_instructor_type_in_part_time_instructors_trigger
AFTER INSERT OR UPDATE OR DELETE ON Part_Time_Instructors
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_instructor_type();

Customers
Fixed syntax errors and added return statement.

-- each customer has credit card
CREATE OR REPLACE FUNCTION check_customer_has_credit_card()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM Most_Recent_Credit_Cards_With_Customers
        WHERE customer_id = COALESCE(NEW.customer_id, OLD.customer_id)) 
    THEN
        RAISE EXCEPTION 'Each customer must have a credit card';
	END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE CONSTRAINT TRIGGER check_customer_has_credit_card_trigger
AFTER INSERT ON Customers 
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_customer_has_credit_card();
CREATE CONSTRAINT TRIGGER check_customer_has_credit_card_trigger_on_cc
AFTER DELETE ON Credit_Cards
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_customer_has_credit_card();
Registers
-- When there is a new value entering the registers/redeems table, check that:
-- Date of registration for a session is before the registration deadline
CREATE OR REPLACE FUNCTION valid_reg_date()
RETURNS TRIGGER AS $$
DECLARE
    _deadline DATE;
BEGIN
    SELECT reg_deadline INTO _deadline FROM Offerings O
        WHERE (O.course_id, O.launch_date) = (NEW.course_id, NEW.launch_date);
    
    IF NEW.reg_date > _deadline THEN
        RAISE EXCEPTION 'The registration date (%) is after the registration deadline (%)', NEW.reg_date, _deadline;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER valid_reg_date_trigger
BEFORE INSERT ON Registers
FOR EACH ROW EXECUTE FUNCTION valid_reg_date();
CREATE TRIGGER valid_reg_date_trigger
BEFORE INSERT ON Redeems
FOR EACH ROW EXECUTE FUNCTION valid_reg_date();

-- When there is a new value entering the registers/redeems table, check that:
-- (customer_id, offering_id) is unique across both tables
CREATE OR REPLACE FUNCTION check_double_registration()
RETURNS TRIGGER AS $$
DECLARE
    _customer_id INTEGER;
BEGIN
    SELECT customer_id INTO _customer_id FROM Credit_Cards cc WHERE cc.credit_card_num = NEW.credit_card_num;
    
    IF EXISTS(SELECT 1 FROM Session_Enrolment S
        WHERE (S.course_id, S.launch_date) = (NEW.course_id, NEW.launch_date)
            AND S.customer_id = _customer_id) THEN
        RAISE EXCEPTION 'Customer (%) has already registered'
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER check_double_registration_on_registers
BEFORE INSERT OR UPDATE ON Registers
FOR EACH ROW EXECUTE FUNCTION check_double_registration();
CREATE TRIGGER check_double_registration_on_redeems
BEFORE INSERT OR UPDATE ON Redeems
FOR EACH ROW EXECUTE FUNCTION check_double_registration();

-- Each instructor must specialise in more than or equal to 1 area
CREATE OR REPLACE FUNCTION check_instructor_specs()
RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT COUNT(*) FROM Instructors)
        = (SELECT COUNT(DISTINCT employee_id) FROM Specializes)
    THEN CASE
        WHEN ((TG_OP = 'INSERT') OR (TG_OP = 'UPDATE')) THEN RETURN NEW;
        WHEN (TG_OP = 'DELETE') THEN RETURN NEW;
        END CASE;
    END IF;
    RAISE EXCEPTION 'Each instructor must specialise in at least one area.';
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER check_instructor_specs_in_instructors
AFTER INSERT OR UPDATE OR DELETE ON Instructors
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_instructor_specs();

CREATE CONSTRAINT TRIGGER check_instructor_specs_in_specializes
AFTER INSERT OR UPDATE OR DELETE ON Specializes
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_instructor_specs();

-- Each customer can have at most one active or partially active package
CREATE OR REPLACE FUNCTION check_active_package()
RETURNS TRIGGER AS $$
BEGIN
    -- this basically means, check if all (id, PARTIALLY/ACTIVE) occurs <= 1
    IF 1 >= ALL (
        SELECT COUNT(*)
        FROM Package_Status
        GROUP BY customer_id, status
        HAVING (status = 'ACTIVE') OR (status = 'PARTIALLY ACTIVE')
    ) THEN RETURN NEW;
    END IF;
    RAISE EXCEPTION 'A customer can only have 1 active or partially active package at a time';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_active_package
BEFORE INSERT OR UPDATE ON Buys
FOR EACH ROW EXECUTE FUNCTION check_active_package();
