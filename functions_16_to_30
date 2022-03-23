---------------------------------------
-- 16. GET_AVAILABLE_COURSE_SESSIONS --
---------------------------------------

CREATE OR REPLACE FUNCTION _get_available_course_sessions_with_sess_num
(IN _course_id INTEGER, IN _launch_date DATE)
RETURNS TABLE
(sess_num INTEGER, sess_date DATE, sess_start_time TIME, instructor_name VARCHAR(500), remaining_seats INTEGER)
BEGIN
    RETURN QUERY
	WITH
		_RelevantSession AS (
			SELECT S.sess_num, S.sess_date, S.sess_start_time, E.employee_name AS instructor_name,
				V.max_capacity - CAST(Enrl.sess_enrolment AS INTEGER) AS remaining_seats
			FROM Sessions S
				NATURAL JOIN Employees E
				NATURAL LEFT JOIN Not_Cancelled_Enrolment_Count Enrl
				NATURAL JOIN Venues V
			WHERE (S.course_id, S.launch_date) = (_course_id, _launch_date)
			AND S.sess_date >= current_date
		)
        -- TODO: actually need to check against registration deadline, because sess_date can be > reg_deadline
		
	SELECT * FROM _RelevantSession X
	WHERE X.remaining_seats > 0;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_available_course_sessions
(IN _course_id INTEGER, IN _launch_date DATE)
RETURNS TABLE
(sess_date DATE, sess_start_time TIME, instructor_name VARCHAR(500), remaining_seats INTEGER)
BEGIN
    RETURN QUERY
    (SELECT S.sess_date, S.sess_start_time, S.instructor_name, S.remaining_seats
    FROM _get_available_course_sessions_with_sess_num(_course_id, _launch_date));
END;
$$ LANGUAGE plpgsql;

--------------------------
-- 17. REGISTER_SESSION --
--------------------------
CREATE OR REPLACE PROCEDURE register_session(_customer_id INTEGER, _course_id INTEGER, _launch_date DATE, _sess_num INTEGER, _payment_method TEXT)
AS $$
DECLARE 
    _credit_card_number VARCHAR(16);
    _package_id INTEGER;
    _buy_date DATE;
BEGIN
    /* _payment_method should only take on either the value 'redemption' or 'credit card payment'. */
    CASE _payment_method
    WHEN 'redemption' THEN
        
        SELECT credit_card_num, package_id, buy_date
            FROM Package_Status 
            WHERE _customer_id = customer_id AND status = 'ACTIVE'
            LIMIT 1
            INTO _credit_card_number, _package_id, _buy_date;
            
        IF _credit_card_number IS NOT NULL THEN
            INSERT INTO Redeems VALUES
                (current_date, _course_id, _launch_date, _sess_num, _package_id, _buy_date, _credit_card_number);
        ELSE
            RAISE EXCEPTION 'Customer does not have a purchased and active course package.';
        END IF;
    
    WHEN 'credit card purchase' THEN
        _credit_card_number := credit_card_num FROM Most_Recent_Credit_Cards_With_Customers WHERE customer_id = _customer_id;
        
        IF _credit_card_number IS NOT NULL THEN
            INSERT INTO Registers VALUES
                (current_date, _course_id, _launch_date, _sess_num, _credit_card_number);
        ELSE
            RAISE EXCEPTION 'Customer % does not have an active credit card.', _customer_id;
        END IF;
        
    ELSE
        RAISE EXCEPTION 'Unknown payment method (%)', _payment_method;
    END CASE;
END;
$$ LANGUAGE plpgsql;

------------------------------
-- 18. GET_MY_REGISTRATIONS --
------------------------------

CREATE OR REPLACE FUNCTION get_my_registrations(_customer_id INTEGER)
RETURNS TABLE (course_title VARCHAR(500), course_fees NUMERIC, 
    session_date DATE, session_start_time TIME,
    session_duration INTEGER, instructor_name VARCHAR(500))
AS $$
BEGIN
    RETURN QUERY
    SELECT title, fees, sess_date, sess_start_time, duration, employee_name FROM (
        SELECT title, fees, sess_date, course_id, duration, launch_date, sess_num, customer_id
        FROM Session_Enrolment NATURAL JOIN Offerings_With_Metadata
        WHERE cancel_date IS NULL) AS _
    NATURAL JOIN Sessions NATURAL JOIN Employees
        WHERE sess_date + sess_start_time > current_timestamp
            AND customer_id = _customer_id;
END;
$$ LANGUAGE plpgsql;

-------------------------------
-- 19. UPDATE_COURSE_SESSION --
-------------------------------

CREATE OR REPLACE PROCEDURE update_course_session
(_customer_id INTEGER, _course_id INTEGER, _launch_date DATE, new_session_number INTEGER)
AS $$
DECLARE
	_type VARCHAR(20);
	prev_sess_num INTEGER;
	_credit_card_num VARCHAR(16);
BEGIN
	IF new_sess_num NOT IN (SELECT sess_num
			  FROM _get_available_course_sessions_with_sess_num(_course_id, _launch_date)) THEN
		RAISE EXCEPTION 'The given session (%) is not available for registration', new_sess_num;
	ELSIF NOT EXISTS (SELECT 1 FROM Session_Enrolment S
			  WHERE (S.course_id, S.launch_date) = (_course_id, _launch_date)
			  AND S.customer_id = _customer_id
			  AND S.cancel_date IS NULL) THEN
		RAISE EXCEPTION 'Either the customer (%) has not registered for this offering (%, %) yet or registration has already been cancelled.', _customer_id, 
			_course_id, _launch_date;
	END IF;
	
	SELECT sess_num, credit_card_num, type
		INTO prev_sess_num, _credit_card_num, _type FROM Session_Enrolment S
	  WHERE (S.course_id, S.launch_date) = (_course_id, _launch_date)
	  AND S.customer_id = _customer_id
      AND S.cancel_date IS NULL;
	  
	IF _type = 'REGISTER' THEN
		UPDATE Registers R
		SET sess_num = new_sess_num, reg_date = current_date,
		WHERE (R.course_id, R.launch_date, R.sess_num) = (_course_id, _launch_date, prev_sess_num)
		AND R.credit_card_num = _credit_card_num;
	ELSIF _type = 'REDEEM' THEN
		-- For a particular session, each credit_card_num should only appear once
		UPDATE Redeems R
		SET sess_num = new_sess_num, redeem_date = current_date
		WHERE (R.course_id, R.launch_date, R.sess_num) = (_course_id, _launch_date, prev_sess_num)
		AND R.credit_card_num = _credit_card_num;	
	END IF;
END;
$$ LANGUAGE plpgsql


-----------------------------
-- 20. CANCEL_REGISTRATION --
-----------------------------
CREATE OR REPLACE PROCEDURE cancel_registration(_customer_id INTEGER, _course_id INTEGER, _launch_date DATE) AS $$
DECLARE
    _sess_num INTEGER;
BEGIN
    -- check if customer used credit card or course package
    IF NOT EXISTS (SELECT 1 FROM Session_Enrolment S
			  WHERE (S.course_id, S.launch_date) = (_course_id, _launch_date)
			  AND S.customer_id = _customer_id
			  AND S.cancel_date IS NULL) THEN
		RAISE EXCEPTION 'Either the customer (%) has not registered for this offering (%, %) yet or registration has already been cancelled.', _customer_id, 
			_course_id, _launch_date;
	END IF;
    
    SELECT S.sess_num INTO _sess_num 
    FROM Session_Enrolment S
    WHERE (S.course_id, S.launch_date) = (_course_id, _launch_date)
        AND S.customer_id = _customer_id
        AND S.cancel_date IS NULL
    LIMIT 1;
              
    INSERT INTO Cancel VALUES (_course_id, _launch_date, _sess_num, _customer_id, current_date);

END;
$$ LANGUAGE plpgsql;

---------------------------
-- 21. UPDATE_INSTRUCTOR --
---------------------------

CREATE OR REPLACE PROCEDURE update_instructor
(_course_id INTEGER, _launch_date DATE, sess_num INTEGER, instructor_id INTEGER)
AS $$
DECLARE
	_sess_date DATE;
	_sess_start_time TIME;
BEGIN
	
	SELECT sess_date, sess_start_time
		INTO _sess_date, _sess_start_time
	FROM Sessions S
	WHERE (S.course_id, S.launch_date, S.sess_num) = (_course_id, _launch_date, _sess_num);
	
	IF _sess_date IS NULL THEN
		RAISE EXCEPTION 'The given session (%, %, %) cannot be found', _course_id, _launch_date, _sess_num;
	ELSIF instructor_id NOT IN(SELECT employee_id FROM find_instructors(_course_id, _sess_date, _sess_start_time)) THEN
		RAISE EXCEPTION 'The given instructor (%) is not available for the given session', instructor_id;
	END IF;
	
	UPDATE Sessions S
	SET employee_id = instructor_id
	WHERE (S.course_id, S.launch_date, S.sess_num) = (_course_id, _launch_date, _sess_num);
END;
$$ LANGUAGE plpgsql;

-------------------------
-- 22. UPDATE_ROOM
------------------------
-- TODO: test this function
CREATE OR REPLACE PROCEDURE update_room (_course_id INTEGER, _sess_num INTEGER, _launch_date DATE, _room_id VARCHAR(100)) AS $$
DECLARE
    _start_time DATETIME;
    _number_registered INTEGER;
    _sess_duration INTEGER;
    _sess_date DATE;
    _sess_start_time TIME;
BEGIN
    -- get the start time of the session in datetime
    _start_time := sess_date + sess_start_time 
        FROM Sessions 
        WHERE (course_id, sess_num, launch_date) = (_course_id, _sess_num, _launch_date);
    -- find the capacity of the new room
    _number_registered := sess_enrolment 
        FROM not_cancelled_enrolment_count 
        WHERE (course_id, sess_num, launch_date) = (_course_id, _sess_num, _launch_date);
    -- find duration of the session
    _sess_duration := EXTRACT (HOUR FROM (SELECT sess_end_time 
        FROM Sessions 
        WHERE (course_id, sess_num, launch_date) = (_course_id, _sess_num, _launch_date))-(SELECT sess_start_time 
        FROM Sessions 
        WHERE (course_id, sess_num, launch_date) = (_course_id, _sess_num, _launch_date)))::INTEGER
    -- find session date
    _sess_date := sess_date 
        FROM Sessions 
        WHERE (course_id, sess_num, launch_date) = (_course_id, _sess_num, _launch_date);
    -- find session start time in time
    _sess_start_time := sess_start_time
        FROM Sessions 
        WHERE (course_id, sess_num, launch_date) = (_course_id, _sess_num, _launch_date);

    -- check that the room is free TODO just use function 8 @minyu
    IF count(find_rooms(_sess_date, _sess_start_time, _sess_duration)) > 0
    THEN
        RAISE EXCEPTION 'Room already booked'
    -- check that the course session has not yet started
    -- check that the number of registrations does not exceed the seating capacity of the new room
    ELSIF (current_timestamp > _start_time OR _number_registered < (SELECT max_capacity FROM Venues WHERE room_id = _room_id)) 
    THEN
        RAISE EXCEPTION 'Update request invalid'
    ELSE 
        UPDATE Sessions
        SET room_id = _room_id
        WHERE (course_id, sess_num, launch_date) = (_course_id, _sess_num, _launch_date)
    END IF;
    

END;
$$ LANGUAGE plpgsql

------------------------
-- 23. REMOVE_SESSION --
------------------------
CREATE OR REPLACE PROCEDURE remove_session
(_course_id INTEGER, _launch_date DATE, _sess_num INTEGER)
AS $$
BEGIN
    /* Catch invalid inputs first */
    -- If session does not exist, reject.
    IF NOT EXISTS (
        SELECT 1 
        FROM Sessions
        WHERE (course_id, launch_date, sess_num) = (_course_id, _launch_date, _sess_num)
    ) THEN
        RAISE EXCEPTION 'Session does not exist.';
    -- If session has already started, reject.
    ELSIF (
        SELECT sess_date + sess_start_time
        FROM Sessions
        WHERE (course_id, launch_date, sess_num) = (_course_id, _launch_date, _sess_num)
    ) <= current_timestamp 
    THEN
        RAISE EXCEPTION 'Cannot remove session that has already been started.';
    -- If session has some enrolment, reject.
    ELSIF EXISTS (
        SELECT 1
        FROM Session_Enrolment
        WHERE (course_id, launch_date, sess_num) = (_course_id, _launch_date, _sess_num)
        AND cancel_date IS NULL
    ) 
    THEN
        RAISE EXCEPTION 'Cannot remove session that has at least one enrolment.';
    ELSE
        DELETE FROM Sessions
        WHERE (course_id, launch_date, sess_num) = (_course_id, _launch_date, _sess_num);
    END IF;
END;
$$ LANGUAGE plpgsql;

---------------------
-- 24. ADD_SESSION --
---------------------
CREATE OR REPLACE PROCEDURE add_session
(_course_id INTEGER, _launch_date DATE, 
 _sess_num INTEGER, _sess_date DATE, _sess_start_time TIME, 
 _instructor_id INTEGER, _room_id VARCHAR(100))
AS $$
DECLARE
    _duration INTEGER;
BEGIN

    _duration := duration FROM Courses WHERE course_id = _course_id;
    IF NOT EXISTS (
        SELECT 1
        FROM find_rooms(_sess_date, _sess_start_time, _duration) Rooms
        WHERE Rooms.room_id = _room_id
    ) THEN
        RAISE EXCEPTION 'Room not available for session.';
    ELSIF NOT EXISTS (
        SELECT 1
        FROM find_instructors(_course_id, _sess_date, _sess_start_time) I
        WHERE I.employee_id = _instructor_id
    ) THEN
        RAISE EXCEPTION 'Instructor not available for session.';
    
    INSERT INTO Sessions VALUES
        (_sess_num, _sess_date, _get_sess_end_time(_duration, _sess_start_time), 
         _sess_start_time, _course_id, _launch_date, _room_id, _instructor_id);
END;
$$ LANGUAGE plpgsql;

--------------------
-- 25. PAY_SALARY --
--------------------
CREATE OR REPLACE FUNCTION _pay_salary_inner(_pay_date DATE)
RETURNS TABLE(employee_id INTEGER, employee_name VARCHAR(500), employee_status TEXT,
             num_work_days INTEGER, num_work_hours INTEGER, hourly_rate NUMERIC, monthly_salary NUMERIC, 
             salary_amount NUMERIC)
AS $$
DECLARE
    curs REFCURSOR;
    r RECORD;
    /* Work_duration can either be the num_hours worked by a part-timer, 
    or the num_days worked by a full-timer. */
    work_duration INTEGER;

    -- for full-timers
    default_first_work_day DATE;
    default_last_work_day DATE;
    first_work_day DATE;
    last_work_day DATE;
    num_days_in_month INTEGER;
BEGIN
    OPEN curs FOR (
        SELECT E.employee_id, E.employee_name, E.date_joined, E.date_departed, PT.hourly_rate, FT.monthly_salary
        FROM Employees E LEFT JOIN Part_Timers PT ON E.employee_id = PT.employee_id
            LEFT JOIN Full_Timers FT ON E.employee_id = FT.employee_id
    );
    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT FOUND;
        
        -- insert into output table
        employee_id := r.employee_id;
        employee_name := r.employee_name;
        
        -- if part-timer
        IF r.hourly_rate IS NOT NULL THEN
            -- call helper function get_working_hrs
            work_duration := get_working_hrs(r.employee_id, 
                                             EXTRACT(MONTH FROM _pay_date)::INTEGER,
                                             EXTRACT(YEAR FROM _pay_date)::INTEGER);
            INSERT INTO Pay_Slips VALUES
                (_pay_date, work_duration, NULL, work_duration * r.hourly_rate, r.employee_id);

            -- insert into output table
            employee_status := 'part-time';
            num_work_days := NULL;
            num_work_hours := work_duration;
            hourly_rate := r.hourly_rate;
            monthly_salary := NULL;
            salary_amount := work_duration * r.hourly_rate;
                
        -- if full-timer        
        ELSIF r.monthly_salary IS NOT NULL THEN
            -- assume first and last work day is the first and last day of the month respectively. 
            -- also keep track of the number of days in the month to calculate the final amount payable.
            default_first_work_day := date_trunc('MONTH', _pay_date)::DATE;
            default_last_work_day := (date_trunc('MONTH', _pay_date)::DATE + INTERVAL '1 MONTH - 1 DAY')::DATE;
            num_days_in_month := EXTRACT(DAY FROM default_last_work_day)::INTEGER;
            
            -- first_work_day = max(default_first, min(date_joined, default_last))
            -- last_work_day = min(default_last, max(date_departed ? date_departed : default_last, default_first))
            first_work_day := GREATEST(default_first_work_day,
                    LEAST(r.date_joined, default_last_work_day));
            last_work_day := LEAST(default_last_work_day,
                    GREATEST(COALESCE(r.date_departed, default_last_work_day), default_first_work_day));
            
            -- number of days worked = (last work day) - (first work day) + 1 
            work_duration := EXTRACT(DAY FROM last_work_day)::INTEGER - EXTRACT(DAY FROM first_work_day)::INTEGER + 1;
            
            INSERT INTO Pay_Slips VALUES
                (_pay_date, NULL, work_duration, work_duration / num_days_in_month * r.monthly_salary , r.employee_id);
            
            -- insert into output table
            employee_status := 'full-time';
            num_work_days := work_duration;
            num_work_hours := NULL;
            hourly_rate := NULL;
            monthly_salary := r.monthly_salary;
            salary_amount := work_duration / num_days_in_month * r.monthly_salary;
            
        END IF;
        RETURN NEXT;
    END LOOP;
    CLOSE curs;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pay_salary()
RETURNS TABLE(employee_id INTEGER, employee_name VARCHAR(500), employee_status TEXT,
             num_work_days INTEGER, num_work_hours INTEGER, hourly_rate NUMERIC, monthly_salary NUMERIC, 
             salary_amount NUMERIC)
AS $$
BEGIN
    RETURN QUERY
        SELECT * FROM _pay_salary_inner(current_date);
END;
$$ LANGUAGE plpgsql;

-------------------------
-- 26. PROMOTE_COURSES --
-------------------------
CREATE OR REPLACE FUNCTION get_inactive_customers()
RETURNS TABLE(customer_id INTEGER)
AS $$
BEGIN
    /* It is fine if the customer cancelled (or otherwise) as cancellation is still a sign of activity */
    /* Anyway, the requirements specified activity as having registered for some course offering 
    in the last 6 months */
    RETURN QUERY
    SELECT DISTINCT C.customer_id 
    FROM Customers C
    WHERE NOT EXISTS (
        SELECT 1 
        FROM Session_Enrolment SE
        WHERE C.customer_id = SE.customer_id
            AND SE.reg_date + INTERVAL '6 MONTHS' >= current_date
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_areas_of_interest()
RETURNS TABLE (customer_id INTEGER, area_name VARCHAR(100))
AS $$
DECLARE
    curs REFCURSOR;
    r RECORD;
BEGIN
    /* returns a table of customer id and all their respective
    areas of interest */
    DROP TABLE IF EXISTS temp_table;
    CREATE TEMP TABLE temp_table (
        _customer_id INTEGER,
        _area_name VARCHAR(500)
    );
    
    OPEN CURS FOR SELECT * FROM get_inactive_customers();
    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT FOUND;
        
        IF EXISTS (
            SELECT 1
            FROM Session_Enrolment SE
            WHERE SE.customer_id = r.customer_id)
        THEN
            INSERT INTO temp_table
                SELECT DISTINCT X.customer_id, X.area_name
            FROM (
                SELECT * 
                FROM Session_Enrolment NATURAL JOIN Courses
                ORDER BY reg_date DESC LIMIT 3
            ) X;
        ELSE
            INSERT INTO temp_table
            SELECT DISTINCT Y.customer_id, A.area_name
            FROM (
                SELECT C.customer_id 
                FROM Customers C
                WHERE C.customer_id = r.customer_id
            ) Y, Areas A;
        END IF;
    END LOOP;
    CLOSE curs;
    
    RETURN QUERY
    SELECT * FROM temp_table;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION promote_courses()
RETURNS TABLE(customer_id INTEGER, customer_name VARCHAR(500), 
              course_area VARCHAR(500), course_id INTEGER, course_title VARCHAR(500),
             launch_date DATE, registration_deadline DATE, offering_fees NUMERIC)
AS $$
BEGIN
    RETURN QUERY
        SELECT AI.customer_id, C.customer_name, AI.area_name, 
            SO.course_id, SO.title, SO.launch_date, SO.reg_deadline, SO.fees
        FROM get_areas_of_interest() AI
            NATURAL JOIN Customers C
            NATURAL JOIN Status_Of_Offerings SO
        WHERE status = 'AVAILABLE' AND
            reg_deadline >= current_date
        ORDER BY AI.customer_id, SO.reg_deadline;
END;
$$ LANGUAGE plpgsql;

----------------------
-- 27. TOP_PACKAGES --
----------------------
CREATE OR REPLACE FUNCTION top_packages
(_n INTEGER)
RETURNS TABLE
(package_id INTEGER, num_free INTEGER, price NUMERIC, start_date DATE, end_date DATE, num_sold INTEGER)
AS $$
BEGIN
	RETURN QUERY
	WITH
	_AggBuys AS (
		SELECT B.package_id, COUNT(*) AS num_sold
		FROM Buys B
		WHERE EXTRACT(YEAR FROM B.buy_date) = EXTRACT(YEAR FROM current_date)
		GROUP BY B.package_id
	),
	_Top5Count AS (
		SELECT DISTINCT X.num_sold
		FROM _AggBuys X
		ORDER BY X.num_sold DESC
		LIMIT _n
	)
	
	SELECT B.package_id, P.max_sess_count, P.price,
		P.start_date, P.end_date, B.num_sold::INTEGER
	FROM _AggBuys B NATURAL JOIN Course_Packages P
	WHERE B.num_sold IN(SELECT * FROM _Top5Count)
	ORDER BY B.num_sold DESC, P.price DESC
	;
END;
$$ LANGUAGE plpgsql;


-------------------------
-- 28. POPULAR_COURSES --
-------------------------

CREATE OR REPLACE FUNCTION popular_courses()
RETURNS TABLE
(course_id INTEGER, course_title VARCHAR(500), course_area VARCHAR(500), num_offerings INTEGER, num_reg_for_latest_offering INTEGER)
AS $$
BEGIN
RETURN QUERY
WITH
	OfferingsInYear AS (
		SELECT O.course_id, O.launch_date, O.start_date, 
			(SELECT SUM(N.sess_enrolment)::INTEGER FROM Not_Cancelled_Enrolment_Count N
			 	WHERE (N.course_id, N.launch_date) = (O.course_id, O.launch_date)
			) AS num_enrolled
		FROM Offerings_With_Metadata O
		WHERE EXTRACT(YEAR FROM O.start_date) = EXTRACT(YEAR FROM current_date)
	),
	AtLeastTwo AS (
		SELECT C.course_id
		FROM Courses C
		WHERE (SELECT COUNT(*) FROM OfferingsInYear O
			WHERE O.course_id = C.course_id
		) >= 2
	),
	RelevantOfferings AS (
		SELECT * FROM OfferingsInYear O
		WHERE O.course_id IN (SELECT * FROM AtLeastTwo)
	),
	CrossProduct AS (
		SELECT R1.course_id,
			R1.launch_date AS launch_date1, R1.start_date AS start_date1, R1.num_enrolled AS num_enrolled1,
			R2.launch_date AS launch_date2, R2.start_date AS start_date2, R2.num_enrolled AS num_enrolled2
		FROM RelevantOfferings R1, RelevantOfferings R2
		WHERE R1.course_id = R2.course_id	 
	),
	PopularCourses AS (
		SELECT cp1.course_id
		FROM CrossProduct cp1
		WHERE NOT EXISTS (
			SELECT 1
			FROM CrossProduct cp2
			WHERE cp1.course_id = cp2.course_id -- (a, a)
			AND cp2.start_date1 > cp2.start_date2 -- (a, b) (b, a)
			AND cp2.num_enrolled1 <= cp2.num_enrolled2
		)
	)
	SELECT p.course_id, C.title, C.area_name,
		(SELECT COUNT(*) FROM OfferingsInYear o WHERE o.course_id = p.course_id)::INTEGER AS num_offerings,
		(SELECT o.num_enrolled FROM OfferingsInYear o
			WHERE o.course_id = p.course_id
		 	AND o.start_date = (SELECT MAX(o2.start_date) FROM OfferingsInYear o2 WHERE o2.course_id = p.course_id)
		) AS num_reg_for_latest_offering
	FROM PopularCourses p NATURAL JOIN Courses C;
END;
$$ LANGUAGE plpgsql;


-----------------------------
-- 29. VIEW_SUMMARY_REPORT
------------------------------
-- input: N (number of months)
-- output: for each month, starting from the current month : month+year, total salary paid, total sales for course packages, total registration by creditcard, total amt of refunds due to cancellation, total number of course registrations via course package

-- TODO test this function
CREATE OR REPLACE FUNCTION view_summary_report(_num_months INTEGER)
RETURNS TABLE(summary_year INTEGER, summary_month INTEGER, total_salary_paid NUMERIC, total_course_packages_sales NUMERIC, total_reg_fees NUMERIC, total_reg_refunds NUMERIC, total_num_redeems INTEGER)
AS $$
BEGIN
    RETURN QUERY
    -- each table has summary_year/month as common columns, join to find fields
    SELECT *
    FROM (
        SELECT EXTRACT(YEAR FROM payment_date)::INTEGER summary_year,
            EXTRACT(MONTH FROM payment_date)::INTEGER summary_month,
            SUM(amount) total_salary_paid
        FROM Pay_Slips
        GROUP BY summary_year, summary_month
    ) Month_Year_Total_Salary_Paid NATURAL JOIN (
    
        SELECT EXTRACT(YEAR FROM buy_date)::INTEGER summary_year,
            EXTRACT(MONTH FROM buy_date)::INTEGER summary_month,
            SUM(price) total_course_packages_sales
        FROM Buys NATURAL JOIN Course_Packages
        GROUP BY summary_year, summary_month
    ) Month_Year_Total_Course_Package_Sales NATURAL JOIN (
    
        SELECT EXTRACT(YEAR FROM buy_date)::INTEGER summary_year,
            EXTRACT(MONTH FROM buy_date)::INTEGER summary_month,
            SUM(fees) total_reg_fees
        FROM Registers_With_Customers NATURAL JOIN Offerings
        GROUP BY summary_year, summary_month
    ) Month_Year_Total_Reg_Fees NATURAL JOIN (
    
        SELECT EXTRACT(YEAR FROM cancel_date)::INTEGER summary_year,
            EXTRACT(MONTH FROM cancel_date)::INTEGER summary_month,
            SUM(refund) total_reg_refunds
        FROM (
            SELECT cancel_date, 
                CASE
                    WHEN cancel_date + 7 <= sess_date THEN 0.9 * fees
                    ELSE 0.0
                END refund
            FROM Registers_With_Customers NATURAL JOIN Offerings
        ) Date_With_Refund
        GROUP BY summary_year, summary_month
        HAVING cancel_date IS NOT NULL
    ) Month_Year_Total_Reg_Refunds NATURAL JOIN (
    
        SELECT EXTRACT(YEAR FROM redeem_date)::INTEGER summary_year,
            EXTRACT(MONTH FROM redeem_date)::INTEGER summary_month,
            COUNT(*) total_num_redeems
        FROM Redeems_With_Customers
        GROUP BY summary_year, summary_month
        HAVING cancel_date IS NULL
    ) Month_Year_Total_Num_Redeems
    
    WHERE DATE (summary_year :: TEXT || '-' || summary_month :: TEXT || '-01')
        <= CURRENT_DATE
    ORDER BY summary_year DESC, summary_month DESC
    LIMIT _num_months;
END;
$$ LANGUAGE plpgsql;

-- i wanna dieeeeeeeeeee LOL same


-----------------------------
-- 30. VIEW_MANAGER_REPORT --
-----------------------------
-- TODO: Test this function
CREATE OR REPLACE FUNCTION _calculate_total_registration_fees
(_course_id INTEGER, _launch_date DATE)
RETURNS NUMERIC
AS $$
BEGIN
    RETURN    
        (SELECT SUM(fees)
        FROM Offerings NATURAL JOIN Registers
        WHERE course_id = _course_id
            AND launch_date = _launch_date)
        +
        (SELECT SUM(price/max_sess_count)
        FROM Redeems NATURAL JOIN Course_Packages
        WHERE course_id = _course_id
            AND launch_date = _launch_date);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION view_manager_report()
RETURNS TABLE(manager_name VARCHAR(500), num_course_areas INTEGER, num_course_offerings INTEGER, total_net_reg_fees NUMERIC, course_title VARCHAR(500))
AS $$
BEGIN
    RETURN QUERY
    WITH
        -- Issue with whether X can be accessed since it is embedded in Prelim_Manager_Report fixed by having X as a separate CTE
        X AS
            (SELECT *
            FROM (Offerings_With_Metadata(course_id, launch_date, fees, end_date)
                NATURAL JOIN Courses(course_id, area_name)
                NATURAL JOIN Areas
                NATURAL JOIN Employees(employee_id, employee_name))),
        Prelim_Manager_Report AS 
            (SELECT employee_name AS manager_name,
                employee_id AS manager_id,
                COUNT(DISTINCT area_name) num_course_areas,
                COUNT(DISTINCT course_id, launch_date) num_course_offerings,
                _calculate_total_registration_fees(course_id, launch_date) total_net_reg_fees
            FROM X
            GROUP BY employee_id
            HAVING (EXTRACT(YEAR FROM end_date)
                    = EXTRACT(YEAR FROM CURRENT_DATE)))
    SELECT manager_name,
        num_course_areas,
        num_course_offerings,
        total_net_reg_fees,
        ARRAY(SELECT DISTINCT title
            FROM X X1
            WHERE total_net_reg_fees = 
                (SELECT MAX(total_net_reg_fees)
                    FROM X X2
                    WHERE X1.manager_id = X2.manager_id)) course_offering_titles
    FROM X;
END;
$$ LANGUAGE plpgsql;
