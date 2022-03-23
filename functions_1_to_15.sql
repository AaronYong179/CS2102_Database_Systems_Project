----------------------
-- HELPER FUNCTIONS --
----------------------

-- Generate session end time
-- Throws exception if it comply with the timing constraints
CREATE OR REPLACE FUNCTION _get_sess_end_time
(IN _duration INTEGER, IN _sess_start_time TIME)
RETURNS TIME AS $$
DECLARE
    _sess_end_time TIME;
    _duration_hr INTERVAL;
    _remaining_duration INTERVAL;
BEGIN
	-- If 12:00 <= start_time < 14:00: illegal
    IF TIME '12:00' <= _sess_start_time AND _sess_start_time < TIME '14:00' THEN
        RAISE EXCEPTION 'Session cannot start between 12:00 and 14:00';
    ELSIF _sess_start_time < TIME '09:00' THEN
        RAISE EXCEPTION 'Session cannot start before 09:00';
    ELSIF _sess_start_time >= TIME '18:00' THEN
        RAISE EXCEPTION 'Session cannot start after 18:00';
    ELSE
		_duration_hr = (_duration * INTERVAL '1 hour');
		
		IF _sess_start_time < TIME '12:00' THEN
			-- if starts before 12:00
			-- from start_time, add duration until 12:00
			-- then from 14:00 continue adding duration until end of duration
			
			_sess_end_time := LEAST(_sess_start_time + _duration_hr, TIME '12:00');
			_remaining_duration = _duration_hr - (_sess_end_time - _sess_start_time);
        
			IF _remaining_duration = INTERVAL '0' THEN
				RETURN _sess_end_time;
			ELSE
				_sess_end_time = TIME '14:00' + _remaining_duration;
				IF _sess_end_time > TIME '18:00' THEN
					RAISE EXCEPTION 'Session cannot end after 18:00. This will end at (%)', _sess_end_time;
				END IF;
				
				RETURN _sess_end_time;
			END IF;
		ELSE
			-- if it starts after >= 14:00
			_sess_end_time = _sess_start_time + _duration_hr;
			IF _sess_end_time > TIME '18:00' THEN
				RAISE EXCEPTION 'Session cannot end after 18:00. This will end at (%)', _sess_end_time;
			END IF;
			
			RETURN _sess_end_time;
		END IF;

    END IF;
END;
$$ LANGUAGE plpgsql;

-- Calculate the number of hours an employee
-- has worked for based on a month and year, using Sessions
CREATE OR REPLACE FUNCTION get_working_hrs
(IN _employee_id INTEGER, IN _month INTEGER, IN _year INTEGER)
RETURNS INTEGER AS $$
DECLARE
    rv INTEGER;
BEGIN
    SELECT COALESCE(SUM(C.duration), 0)
        INTO rv
    FROM Sessions S INNER JOIN Courses C
        ON S.course_id = C.course_id
    WHERE S.employee_id = _employee_id
    AND CAST(EXTRACT(MONTH FROM S.sess_date) AS INTEGER) = _month
    AND CAST(EXTRACT(YEAR FROM S.sess_date) AS INTEGER) = _year;
    
    RETURN rv;
END;
$$ LANGUAGE plpgsql;

---------------------
-- 1. ADD_EMPLOYEE --
---------------------
-- HELPER PROCEDURE
CREATE OR REPLACE PROCEDURE _add_employee_course_areas(employee_id INTEGER, 
    employee_type TEXT, course_areas TEXT[])
AS $$
/* Adds all course_areas present in an array of course_areas to the 
Areas or Specializes table, depending on the employee_type */
DECLARE
    area_name TEXT;
BEGIN
    FOREACH area_name IN ARRAY course_areas LOOP
        IF employee_type = 'manager' THEN
            INSERT INTO Areas VALUES (area_name, employee_id);
        ELSIF employee_type = 'instructor' THEN 
            INSERT INTO Specializes VALUES (employee_id, area_name);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE add_employee
(employee_name VARCHAR(500), address TEXT, contact_num VARCHAR(100),
email VARCHAR(100), salary_amt NUMERIC, salary_type TEXT, date_joined DATE,
employee_type TEXT, course_areas TEXT[] DEFAULT '{}')
AS $$
DECLARE
    new_id INTEGER;
BEGIN
    -- Catch invalid data (course_areas must be empty for admins and non-empty for instructors)
    IF employee_type = 'administrator' AND course_areas <> '{}' THEN
    	RAISE EXCEPTION 'The set of course_areas for administrators must be empty';
    ELSIF employee_type = 'instructor' AND course_areas = '{}' THEN
        RAISE EXCEPTION 'The set of course_areas for instructors must not be empty';
    END IF;

    INSERT INTO Employees(employee_name, contact_num, email, address, date_joined, date_departed)
    VALUES (employee_name, contact_num, email, address, date_joined, NULL)
    RETURNING employee_id INTO new_id;
	
	CASE salary_type
	WHEN 'full-time' THEN
		INSERT INTO Full_Timers VALUES (new_id, salary_amt);
		
		CASE employee_type
		WHEN 'administrator' THEN
			INSERT INTO Administrators VALUES (new_id);
		WHEN 'instructor' THEN
			INSERT INTO Instructors VALUES (new_id);
			INSERT INTO Full_Time_Instructors VALUES (new_id);
			CALL _add_employee_course_areas(new_id, employee_type, course_areas);
		WHEN 'manager' THEN
			INSERT INTO Managers VALUES (new_id);
			CALL _add_employee_course_areas(new_id, employee_type, course_areas);
		ELSE
			RAISE EXCEPTION 'Invalid employee_type given (%)', employee_type;
		END CASE;
			
	WHEN 'part-time' THEN
		IF employee_type = 'instructor' THEN
			INSERT INTO Part_Timers VALUES (new_id, salary_amt);
			INSERT INTO Instructors VALUES (new_id);
			INSERT INTO Part_Time_Instructors VALUES (new_id);
			CALL _add_employee_course_areas(new_id, employee_type, course_areas);
		ELSE
			RAISE EXCEPTION 'Invalid employee_type given (%)', employee_type;
		END IF;
	ELSE
		RAISE EXCEPTION 'Invalid salary_type given (%)', salary_type;
	END CASE;
		
END;
$$ LANGUAGE plpgsql;

------------------------
-- 2. REMOVE_EMPLOYEE --
------------------------
CREATE OR REPLACE PROCEDURE remove_employee(_employee_id INTEGER, _date_departed DATE)
AS $$
BEGIN
	IF EXISTS(
		SELECT 1 FROM Offerings 
		WHERE employee_id = _employee_id 
			AND reg_deadline > _date_departed) THEN
			RAISE EXCEPTION 'Unable to remove administrator handling offering after the input departure date.';
	ELSIF EXISTS(
		SELECT 1 FROM Sessions 
		WHERE employee_id = _employee_id 
			AND sess_date > _date_departed) THEN
			RAISE EXCEPTION 'Unable to remove instructor teaching session after the input departure date.';
	ELSIF EXISTS(
		SELECT 1 FROM Areas 
		WHERE employee_id = _employee_id) THEN
		RAISE EXCEPTION 'Unable to remove manager who is managing an area.';
        
    -- Raise exception if employee has already been removed.
	ELSIF EXISTS(
		SELECT 1 FROM Employees
		WHERE employee_id = _employee_id
			AND date_departed IS NOT NULL) THEN
		RAISE EXCEPTION 'Employee (%) has already been removed', _employee_id;
	ELSE
		UPDATE Employees SET date_departed = _date_departed 
		WHERE employee_id = _employee_id; 
	END IF;
END;
$$ LANGUAGE plpgsql;

---------------------
-- 3. ADD_CUSTOMER --
---------------------
CREATE OR REPLACE PROCEDURE add_customer
(customer_name VARCHAR(100), address TEXT, contact_num VARCHAR(100), email VARCHAR(100), 
credit_card_num CHAR(16), expiry_date VARCHAR(7), cvv CHAR(3))
AS $$
DECLARE
    new_id INTEGER;
    padded_expiry_date DATE;
BEGIN
-- TODO: need to check if the credit card is currently active or not
    INSERT INTO Customers(customer_name, address, email, contact_num) 
    VALUES (customer_name, address, email, contact_num) 
    RETURNING customer_id INTO new_id;
	
    -- expiry_date needs to be of the form MM-YYYY
    -- the function will padd the input expiry_date with an arbitrary day 01,
    --    since credit cards do not have an expiry day.
    padded_expiry_date := TO_DATE('01-' || expiry_date, 'DD-MM-YYYY');
    IF padded_expiry_date < current_date THEN
        RAISE EXCEPTION 'Invalid credit card. Credit card has expired.';
    END IF;
    
    INSERT INTO Credit_Cards
    VALUES (credit_card_num, cvv, padded_expiry_date, new_id, current_timestamp);
END;
$$ LANGUAGE plpgsql;

---------------------------
-- 4. UPDATE_CREDIT_CARD --
---------------------------

CREATE OR REPLACE PROCEDURE update_credit_card
(_customer_id INTEGER, _credit_card_number CHAR(16), _expiry_date VARCHAR(7), _cvv CHAR(3))
AS $$
/* Allows the update of a single column (cvv/expiry_date) as long as the credit_card_num is the same */
/* customer_id for a existing credit_card_number cannot be updated an will simply be ignored */
/* A new credit_card_number inserts a new row into the Credit_Cards table */
DECLARE padded_expiry_date DATE;
BEGIN
    padded_expiry_date := TO_DATE('01-' || _expiry_date, 'DD-MM-YYYY');
    
    IF padded_expiry_date < current_date THEN
        RAISE EXCEPTION 'Invalid credit card. Credit card has expired.';
    END IF;
    
    INSERT INTO Credit_Cards AS CC VALUES
        (_credit_card_number, _cvv, padded_expiry_date, _customer_id, current_timestamp)
    ON CONFLICT (credit_card_num) DO UPDATE
        SET cvv = _cvv,
            expiry_date = padded_expiry_date,
            from_date = current_timestamp
        WHERE CC.customer_id = _customer_id;
END;
$$ LANGUAGE plpgsql;

-------------------
-- 5. ADD_COURSE --
-------------------

CREATE OR REPLACE PROCEDURE add_course
(course_title VARCHAR(500), course_description TEXT, course_area VARCHAR(500), duration INTEGER)
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Areas A WHERE A.area_name = course_area) THEN
        RAISE EXCEPTION 'Invalid course area (%) cannot be found', course_area;
    END IF;
    
    INSERT INTO Courses(title, duration, description, area_name)
    VALUES (course_title, duration, course_description, course_area);
END;
$$ LANGUAGE plpgsql;

-------------------------
-- 6. FIND_INSTRUCTORS --
-------------------------

CREATE OR REPLACE FUNCTION find_instructors
(IN _course_id INTEGER, IN _sess_date DATE, IN _sess_start_time TIME)
RETURNS TABLE (employee_id INTEGER, employee_name VARCHAR(500))
AS $$
DECLARE
    _area_name VARCHAR(500);
    _duration INTEGER;
    _sess_end_time TIME;
BEGIN      
    -- 1. get the corresponding course area
    SELECT area_name, duration
        INTO _area_name, _duration
    FROM Courses C
    WHERE C.course_id = _course_id;
    
    _sess_end_time = _get_sess_end_time(_duration, _sess_start_time);
    
    RETURN QUERY
    WITH
        -- 2. get list of instructors that specialise in said area
        -- and has not departed
        L1 AS (
            SELECT S.employee_id
            FROM Specializes S NATURAL JOIN Employees E
            WHERE S.area_name = _area_name
            -- TODO: doesnt sit well with jiefeng
            AND E.date_departed IS NULL
        ),
        -- 3. from L1, delete instructors that are busy between sess_start_time and sess_end_time
        L2 AS (
            SELECT L1.employee_id
            FROM L1
            WHERE NOT EXISTS (
                SELECT 1
                FROM Sessions S
                WHERE S.employee_id = L1.employee_id
                AND S.sess_date = _sess_date
                AND (S.sess_start_time, S.sess_end_time)
                    OVERLAPS (_sess_start_time, _sess_end_time)
            )
        ),
        -- 4. For each instructor in L2, check that they have a break
        L3 AS (
            SELECT L2.employee_id
            FROM L2
            WHERE NOT EXISTS (
                SELECT 1
                FROM Sessions S
                WHERE S.employee_id = L2.employee_id
                AND S.sess_date = _sess_date
                AND S.sess_end_time + INTERVAL '1 hour' > _sess_start_time
            )
            AND NOT EXISTS (
                SELECT 1
                FROM Sessions S
                WHERE S.employee_id = L2.employee_id
                AND S.sess_date = _sess_date
                AND _sess_end_time + INTERVAL '1 hour' < S.sess_start_time 
            )
        ),
        -- 5. For each instructor in L3, if they are part-timers, check that they will not exceed 30hours in that month
        L4 AS (
            SELECT L3.employee_id
            FROM L3
            WHERE L3.employee_id IN (
                SELECT FT.employee_id
                FROM Full_Time_Instructors FT
            )
            OR get_working_hrs(
                L3.employee_id,
                CAST(EXTRACT(MONTH FROM CURRENT_DATE) AS INTEGER),
                CAST(EXTRACT(YEAR FROM CURRENT_DATE) AS INTEGER)
            ) <= (30 - _duration)
        )
        
        SELECT L4.employee_id, E.employee_name
        FROM L4 NATURAL JOIN Employees E;
END;
$$ LANGUAGE plpgsql;

----------------------------------
-- 7. GET_AVAILABLE_INSTRUCTORS --
----------------------------------

CREATE OR REPLACE FUNCTION _find_available_timings
(IN _course_id INTEGER, IN _employee_id INTEGER, IN day DATE)
RETURNS TIME[]
AS $$
DECLARE
    st TIME;
    possible_start_times TIME [];
    rv TIME[];
BEGIN
    possible_start_times = '{09:00, 10:00, 11:00, 14:00, 15:00, 16:00, 17:00}';
    rv = '{}';
    
    FOREACH st IN ARRAY possible_start_times LOOP
        IF EXISTS(SELECT 1 FROM find_instructors(_course_id, day, st) Qry
            WHERE Qry.employee_id = _employee_id) THEN
            rv = array_append(rv, st);
        END IF;
    END LOOP;
    
    RETURN rv;
    
EXCEPTION WHEN OTHERS THEN
    RETURN rv;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_available_instructors
(IN _course_id INTEGER, IN _start_date DATE, IN _end_date DATE)
RETURNS TABLE
(employee_id INTEGER, employee_name VARCHAR(500), total_num_hrs_in_the_month INTEGER, day DATE, available_hrs TIME[])
AS $$
DECLARE
    _area_name VARCHAR(500);
    _duration INTEGER;
    _sess_end_time TIME;
    curs REFCURSOR;
    r RECORD;
BEGIN
    SELECT area_name, duration
        INTO _area_name, _duration
    FROM Courses C
    WHERE C.course_id = _course_id;
    
    OPEN curs FOR (
        WITH
        _Instructors AS (
            SELECT S.employee_id, E.employee_name
            FROM Specializes S NATURAL JOIN Employees E
            WHERE S.area_name = _area_name
            AND E.date_departed IS NULL
        ),
        _EnumDates AS (
            SELECT generate_series::DATE AS day
            FROM GENERATE_SERIES(_start_date, _end_date, INTERVAL '1 day')
            WHERE EXTRACT(DOW FROM generate_series) IN ('1', '2', '3', '4', '5')
        )
        SELECT I.employee_id, I.employee_name,
        get_working_hrs(
            I.employee_id,
            CAST(EXTRACT(MONTH FROM CURRENT_DATE) AS INTEGER),
            CAST(EXTRACT(YEAR FROM CURRENT_DATE) AS INTEGER)
        ) AS numHours, E.day
        FROM _Instructors I, _EnumDates E
        ORDER BY I.employee_id, day
    );
    
    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT FOUND;
        
        employee_id := r.employee_id;
        employee_name := r.employee_name;
        total_num_hrs_in_the_month := r.numHours;
        day := r.day;
        available_hrs := _find_available_timings(_course_id, r.employee_id, r.day);
        
        RETURN NEXT;
    END LOOP;
    CLOSE curs;  
END;
$$ LANGUAGE plpgsql;

-------------------
-- 8. FIND_ROOMS --
-------------------

CREATE OR REPLACE FUNCTION find_rooms(_sess_date DATE, _sess_start_time TIME, _sess_duration INTEGER)
RETURNS TABLE(room_id VARCHAR(100))
AS $$
DECLARE
    _sess_end_time TIME;
BEGIN
    _sess_end_time := _get_sess_end_time(_sess_duration, _sess_start_time);
    RETURN QUERY
        SELECT V.room_id FROM Venues V
        WHERE NOT EXISTS(
            SELECT 1 FROM Sessions S
            WHERE sess_date = _sess_date
            AND V.room_id = S.room_id
            AND (sess_start_time, sess_end_time) 
                OVERLAPS(_sess_start_time, _sess_end_time)
        );
END;
$$ LANGUAGE plpgsql;

----------------------------
-- 9. GET_AVAILABLE_ROOMS --
----------------------------

CREATE OR REPLACE FUNCTION _get_available_room_timings
(IN _date DATE, IN _room_id VARCHAR(100), IN _duration INTEGER)
RETURNS TIME[]
AS $$
DECLARE
    st TIME;
    possible_start_times TIME [];
    rv TIME[];
BEGIN
    possible_start_times := '{09:00, 10:00, 11:00, 14:00, 15:00, 16:00, 17:00}';
    rv = '{}';
    
    FOREACH st IN ARRAY possible_start_times LOOP
        IF EXISTS(SELECT 1 FROM find_rooms(_date, st, _duration) Qry
            WHERE Qry.room_id = _room_id) THEN
            rv = array_append(rv, st);
        END IF;
    END LOOP;
    
    RETURN rv;
    
EXCEPTION WHEN OTHERS THEN
    RETURN rv;
END;
$$ LANGUAGE plpgsql;

-- TODO: the printout is wrong right? this function needs a duration field
CREATE OR REPLACE FUNCTION get_available_rooms
(IN _start_date DATE, IN _end_date DATE, IN _duration INTEGER)
RETURNS TABLE
(room_id VARCHAR(100), room_capacity INTEGER, day DATE, free_hours TIME[])
AS $$
DECLARE
    curs REFCURSOR;
    r RECORD;
BEGIN
    OPEN curs FOR (
        WITH
        _EnumDates AS (
            SELECT generate_series::DATE AS day
            FROM GENERATE_SERIES(_start_date, _end_date, INTERVAL '1 day')
            WHERE EXTRACT(DOW FROM generate_series) IN ('1', '2', '3', '4', '5')
        )
        SELECT V.room_id, V.max_capacity, E.day
        FROM Venues V, _EnumDates E
        ORDER BY V.room_id, E.day
    );

    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT FOUND;
        
        room_id := r.room_id;
        room_capacity := r.max_capacity;
        day := r.day;
        free_hours := _get_available_room_timings(r.day, r.room_id, _duration);
        
        RETURN NEXT;
    END LOOP;
    CLOSE curs;
END;
$$ LANGUAGE plpgsql;

-----------------------------
-- 10. ADD_COURSE_OFFERING --
-----------------------------

DROP TYPE IF EXISTS SESS_INPUT CASCADE;
CREATE TYPE SESS_INPUT AS (
    sess_date DATE,
    sess_start_time TIME,
    room_id VARCHAR(100)
);

CREATE OR REPLACE FUNCTION _sess_input_as_tbl
(sess_inputs SESS_INPUT[], _course_id INTEGER, _launch_date DATE, _duration INTEGER)
RETURNS TABLE
(sess_num INTEGER, course_id INTEGER, launch_date DATE,
sess_date DATE, sess_start_time TIME, sess_end_time TIME, 
room_id VARCHAR(100))
AS $$
DECLARE
    sess_in SESS_INPUT;
    curs REFCURSOR;
    counter INTEGER;
BEGIN
    counter = 1;
    
    OPEN curs FOR (
        SELECT 1, 2, 3, 4
    );
    
    FOREACH sess_in IN ARRAY sess_inputs LOOP
        sess_num = counter;
        course_id = _course_id;
        launch_date = _launch_date;
        sess_date = sess_in.sess_date;
        sess_start_time = sess_in.sess_start_time;
        sess_end_time = _get_sess_end_time(_duration, sess_in.sess_start_time);
        room_id = sess_in.room_id;
        RETURN NEXT;
        
        counter = counter + 1;
    END LOOP;
    
    CLOSE curs;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION _assign_instructors
(sess_inputs SESS_INPUT[], _course_id INTEGER, _launch_date DATE, _duration INTEGER,
_start_date DATE, _end_date DATE)
RETURNS TABLE
(sess_num INTEGER, course_id INTEGER, launch_date DATE,
sess_date DATE, sess_end_time TIME, sess_start_time TIME,
room_id VARCHAR(100), employee_id INTEGER)
AS $$
DECLARE
    curs CURSOR FOR (SELECT * FROM _sess_input_as_tbl(sess_inputs, _course_id, _launch_date, _duration) Qry
        ORDER BY Qry.sess_date, Qry.sess_start_time);
    r RECORD;
    instructor_found INTEGER;
    hr TIME;
    old_available_hrs TIME[];
    new_available_hrs TIME[];
BEGIN
    CREATE TEMP TABLE LookupTable (
        employee_id INTEGER,
        employee_name VARCHAR(500),
        total_num_hours_in_the_month INTEGER,
        day DATE,
        available_hours TIME[],
        type VARCHAR(2)
    )
    ON COMMIT DROP;
    
    INSERT INTO LookupTable
    (SELECT *,
        (CASE
            WHEN EXISTS(SELECT 1 FROM Full_Time_Instructors FT NATURAL JOIN Employees E
                WHERE FT.employee_id = Qry.employee_id AND E.date_departed IS NULL)
                THEN 'FT'
            WHEN EXISTS(SELECT 1 FROM Part_Time_Instructors PT NATURAL JOIN Employees E
                WHERE PT.employee_id = Qry.employee_id AND E.date_departed IS NULL)
                THEN 'PT'
        END)
    FROM get_available_instructors(_course_id, _start_date, _end_date) Qry
    );
    
    OPEN curs;
    
    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT FOUND;
        
        sess_num = r.sess_num;
        course_id = r.course_id;
        launch_date = r.launch_date;
        sess_date = r.sess_date;
        sess_start_time = r.sess_start_time;
        sess_end_time = r.sess_end_time;
        room_id = r.room_id;
        
        SELECT L.employee_id, L.available_hours FROM LookupTable L
            INTO instructor_found, old_available_hrs
        WHERE L.day = sess_date
        AND sess_start_time IN (SELECT * FROM UNNEST(L.available_hours))
        AND (L.type = 'FT' OR (L.type = 'PT' AND L.total_num_hours_in_the_month <= 30 - _duration))
        LIMIT 1;
        
        IF instructor_found IS NULL THEN
            RAISE EXCEPTION 'Cannot auto-assign instructors';
        ELSE
            employee_id = instructor_found;
            new_available_hrs = '{}';
            
            FOREACH hr IN ARRAY old_available_hrs LOOP
                -- TODO: check if this is okay with the whole break thing
                IF sess_start_time - INTERVAL '1 hour' <= hr
                    AND hr < sess_end_time + INTERVAL '1 hour' THEN
                    CONTINUE;
                ELSE
                    new_available_hrs = array_append(new_available_hrs, hr);
                END IF;
            END LOOP;
            
            -- RAISE NOTICE 'Session at (%, %) | Instructor (%) | New free hrs (%)', sess_start_date, sess_start_time, employee_id, new_available_hours;
            UPDATE LookupTable L
            SET total_num_hours_in_the_month = L.total_num_hours_in_the_month + _duration,
                available_hours = new_available_hrs
            WHERE L.employee_id = instructor_found AND L.day = sess_date;
        END IF;
        
        RETURN NEXT;
    END LOOP;
    
    CLOSE curs;
END;
$$ LANGUAGE plpgsql;

-- TODO: Excluded offering_id because its irrelevant for this schema
CREATE OR REPLACE PROCEDURE add_course_offering
(_course_id INTEGER, fees NUMERIC, launch_date DATE, reg_deadline DATE, admin_id INTEGER, sess_inputs SESS_INPUT[], target_reg INTEGER)
AS $$
DECLARE
    sess_input_size INTEGER;
    input_i SESS_INPUT;
    input_j SESS_INPUT;
    earliest_sess DATE;
    latest_sess DATE;
    _duration INTEGER;
	_count_venue_capacity INTEGER;
BEGIN
	_count_venue_capacity = 0;
	
    -- check at least 1 session
    sess_input_size := (SELECT CARDINALITY(sess_inputs));
    IF sess_input_size = 0 THEN
        RAISE EXCEPTION 'Each course offering must have at least one session.';
    END IF;
    
    SELECT duration INTO _duration FROM Courses C WHERE C.course_id = _course_id;
    IF _duration IS NULL THEN
        RAISE EXCEPTION 'Given course_id (%) cannot be found', _course_id;
    END IF;
    
    earliest_sess := sess_inputs[1].sess_date;
    latest_sess := sess_inputs[1].sess_date;
    
    FOR i IN 1..sess_input_size - 1 LOOP
        input_i = sess_inputs[i];
        
        -- check all inputs are disjoint
        FOR j IN i+1..sess_input_size LOOP
            input_j = sess_inputs[j];
            IF (input_i.sess_date = input_j.sess_date
                AND (input_i.sess_start_time, _get_sess_end_time(_duration, input_i.sess_start_time))
                    OVERLAPS (input_j.sess_start_time, _get_sess_end_time(_duration, input_j.sess_start_time))
                ) THEN
                RAISE EXCEPTION 'The given sessions at (%) and (%) overlap with each other', i, j;
            END IF;
        END LOOP;
	END LOOP;
	
    FOR i IN 1..sess_input_size LOOP
		input_i = sess_inputs[i];
		
        -- check if the room_id given is valid
        IF input_i.room_id NOT IN (SELECT room_id FROM find_rooms(input_i.sess_date, input_i.sess_start_time, _duration)) THEN
            RAISE EXCEPTION 'The session at (%) cannot be held at room (%)', i, input_i.room_id;
        END IF;
		
		-- count venue capacity
		_count_venue_capacity := _count_venue_capacity + (SELECT V.max_capacity FROM Venues V WHERE V.room_id = input_i.room_id);
		
        -- determine earliest/latest sessions
        IF (input_i.sess_date) < earliest_sess THEN
            earliest_sess := input_i.sess_date;
        END IF;
        IF (input_i.sess_date) > latest_sess THEN
            latest_sess := input_i.sess_date;
        END IF;

    END LOOP;
    
    -- check if reg deadline is valid
    IF reg_deadline + INTERVAL '10 days' > earliest_sess THEN
        RAISE EXCEPTION 'Registration deadline (%) must be at least 10 days before the earliest session (%)', reg_deadline, earliest_sess;
    END IF;
	
	-- check room_capacity >= target_reg
	IF _count_venue_capacity < target_reg THEN
		RAISE EXCEPTION 'The seating capacity of the given offering (%) is less than the target registration (%)', _count_venue_capacity, target_reg;
	END IF;
    
    RAISE NOTICE 'Earliest is (%) | Latest is (%)', earliest_sess, latest_sess;
    
    WITH
        _AssignInstructors AS (
            SELECT *
            FROM _assign_instructors(
                sess_inputs,
                _course_id, launch_date,
                _duration,
                earliest_sess, latest_sess
            )
        ),
        _InsertOfferings AS (
            INSERT INTO Offerings
            VALUES
            (_course_id, launch_date, fees, target_reg, reg_deadline, admin_id)
        )
    
    INSERT INTO Sessions(sess_num, course_id, launch_date, sess_date, sess_end_time, sess_start_time, room_id, employee_id)
    (SELECT * FROM _AssignInstructors);
END;
$$ LANGUAGE plpgsql;

----------------------------
-- 11. ADD_COURSE_PACKAGE --
----------------------------
CREATE OR REPLACE PROCEDURE add_course_package 
(package_name VARCHAR(500), max_sess_count INTEGER, start_date DATE, end_date DATE, price NUMERIC)
AS $$
BEGIN
    INSERT INTO 
        Course_Packages(package_name, price, max_sess_count, start_date, end_date) 
    VALUES
        (package_name, price, max_sess_count, start_date, end_date);
END;
$$ LANGUAGE plpgsql;

---------------------------------------
-- 12. GET_AVAILABLE_COURSE_PACKAGES --
---------------------------------------
CREATE OR REPLACE FUNCTION get_available_course_packages()
RETURNS TABLE(package_name VARCHAR(500), max_sess_count INTEGER, end_date DATE, price NUMERIC)
AS $$
BEGIN
/* Get all course_packages that have not expired by :current_date or have no expiry date. */ 
    RETURN QUERY
        SELECT CP.package_name, CP.max_sess_count, CP.end_date, CP.price 
        FROM Course_Packages AS CP
        WHERE (CP.end_date IS NULL) OR (CP.end_date >= current_date);
END;
$$ LANGUAGE plpgsql;

----------------------------
-- 13. BUY_COURSE_PACKAGE --
----------------------------
CREATE OR REPLACE PROCEDURE buy_course_package
(_customer_id INTEGER, _package_id INTEGER)
AS $$
DECLARE
_credit_card_num CHAR(16);
BEGIN
    _credit_card_num = credit_card_num
        FROM Most_Recent_Credit_Cards_With_Customers, Course_Packages
        WHERE package_id = _package_id AND customer_id = _customer_id;
    -- Checks if customer already has an active/partially active package
    IF EXISTS (
        SELECT 1 
        FROM Package_Status
        WHERE status <> 'INACTIVE'
            AND customer_id = _customer_id
    ) THEN RAISE EXCEPTION 'Customer already has an active/partially active package.';
    END IF;
    /* Checks if package_id and customer_id combination exists. 
    If exists, then a new record in inserted into table Buys */
    /* Most_Recent_Credit_Cards_With_Customers already filters out expired
    credit cards */
    IF _credit_card_num IS NOT NULL THEN
        INSERT INTO Buys VALUES
            (current_date, _package_id, _credit_card_num);
    ELSE
        RAISE EXCEPTION 'Transaction is not valid. package_id (%) and/or customer_id (%) does not exist', _package_id, _customer_id;
    END IF;
END;
$$ LANGUAGE plpgsql;
-------------------------------
-- 14. GET_MY_COURSE_PACKAGE --
-------------------------------
CREATE OR REPLACE FUNCTION get_my_course_package(_customer_id INTEGER)
RETURNS json AS $$
DECLARE
    output_json jsonb;
    redeemed_info_json jsonb;
BEGIN
    /* Get package_name, buy_date, price, max_sess_count, remaining_redemptions
    where the package is still active/partially active and format as JSON. */
    output_json := row_to_json(My_Course_Package_Information) 
    FROM (
        SELECT package_name, buy_date, price, max_sess_count, remaining_redemptions
        FROM Package_Status 
            NATURAL JOIN Course_Packages 
            NATURAL JOIN Num_Remaining_Redemptions
        WHERE customer_id = _customer_id
            AND status <> 'INACTIVE'
    ) AS My_Course_Package_Information;
    
    /* Get all the redeemed sessions using the active/partially active package's id
    and format into an array of dictionaries [{}, {}, {}, ...]*/
    redeemed_info_json := json_agg(
        json_build_object('title', title, 'sess_date', sess_date, 'sess_start_time', sess_start_time)
    ) 
    FROM (
        SELECT title, sess_date, sess_start_time
        FROM Redeems_With_Customers 
            NATURAL JOIN Courses 
            NATURAL JOIN Sessions
        WHERE customer_id = _customer_id
            AND cancel_date IS NOT NULL
            AND package_id = (
                SELECT package_id 
                FROM Package_Status
                WHERE customer_id = _customer_id
                    AND status <> 'INACTIVE'
            )
    ) AS Redeemed_Information;
    
    /* Merge the two queries together, and assign the key 'redeemed_sessions' to
    the array of redeemed sessions */
    RETURN output_json || json_build_object('redeemed_sessions', redeemed_info_json)::jsonb;
END;
$$ LANGUAGE plpgsql;

----------------------------------------
-- 15. GET_AVAILABLE_COURSE_OFFERINGS --
----------------------------------------
CREATE OR REPLACE FUNCTION get_available_course_offerings()
RETURNS TABLE(title VARCHAR(500), area_name VARCHAR(500), start_date DATE, end_date DATE, reg_deadline DATE, fees NUMERIC, num_of_remaining_seats INTEGER) AS $$
BEGIN
    RETURN QUERY
        WITH
            L1 AS (
                SELECT X.title, X.area_name, 
                    X.start_date, X.end_date, 
                    X.reg_deadline, X.fees,
                    CAST((sum_capacity - (
                        SELECT COALESCE(SUM(sess_enrolment), 0)
                        FROM Not_Cancelled_Enrolment_Count N
                        WHERE N.course_id = X.course_id
                            AND N.launch_date = X.launch_date)
                    ) AS INTEGER) AS num_of_remaining_seats
                FROM (Offerings_With_Metadata
                        NATURAL JOIN Courses) X
            )
        SELECT *
        FROM L1
        WHERE L1.reg_deadline <= CURRENT_DATE
        AND L1.num_of_remaining_seats > 0
        ;
END;
$$ LANGUAGE plpgsql;
