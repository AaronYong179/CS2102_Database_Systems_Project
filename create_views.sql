CREATE OR REPLACE VIEW Registers_With_Customers AS
-- course_id, launch_date, sess_num, sess_date,
-- reg_date, credit_card_num, customer_id, cancel_date
    WITH
        _Registers_With_Customers AS (
            SELECT 
                R.course_id, R.launch_date, R.sess_num,
                R.reg_date,
                R.credit_card_num, Card.customer_id,
                (SELECT cancel_date
                FROM Cancels cxl
                WHERE cxl.course_id = R.course_id
                    AND cxl.launch_date = R.launch_date
                    AND cxl.sess_num = R.sess_num
                    AND cxl.customer_id = Card.customer_id
                ) AS cancel_date
            FROM Registers R
                NATURAL JOIN Credit_Cards Card
        )
    
    SELECT
        -- Session
        R.course_id, R.launch_date, R.sess_num,
        -- Session information
        S.sess_date,
        -- Registration date
        R.reg_date,
        -- Customer information
        R.credit_card_num, R.customer_id,
        -- Cancellation date, if any
        R.cancel_date
    FROM _Registers_With_Customers R
        LEFT JOIN Sessions S 
            ON R.course_id = S.course_id
            AND R.launch_date = S.launch_date
            AND R.sess_num = S.sess_num
;

CREATE OR REPLACE VIEW Redeems_With_Customers AS
-- course_id, launch_date, sess_num, sess_date, redeem_date
-- credit_card_num, customer_id, cancel_date,
-- package_id, buy_date, package_name, max_sess_count,
-- start_date, end_date
    WITH
        _Redeems_With_Customers AS (
            SELECT
                R.course_id, R.launch_date, R.sess_num,
                R.redeem_date,
                R.credit_card_num, Card.customer_id,
                (SELECT cancel_date
                FROM Cancels cxl
                WHERE cxl.course_id = R.course_id
                    AND cxl.launch_date = R.launch_date
                    AND cxl.sess_num = R.sess_num
                    AND cxl.customer_id = Card.customer_id
                ) AS cancel_date,        
                R.package_id, R.buy_date,
                Pck.package_name, Pck.max_sess_count,
                Pck.start_date, Pck.end_date
        FROM (Redeems R
            NATURAL JOIN Credit_Cards Card)
            NATURAL JOIN Course_Packages Pck
        )
    
    SELECT
        -- Session
        R.course_id, R.launch_date, R.sess_num,
        -- Session information
        S.sess_date,
        -- Redemption date
        R.redeem_date,
        -- Customer information
        R.credit_card_num, R.customer_id,
        -- Cancellation date
        R.cancel_date,
        -- Redemption information
        R.package_id, R.buy_date,
        R.package_name, R.max_sess_count,
        R.start_date, R.end_date
    FROM _Redeems_With_Customers R
        LEFT JOIN Sessions S
            ON R.course_id = S.course_id
            AND R.launch_date = S.launch_date
            AND R.sess_num = S.sess_num
;

-- Just a union of Registers and Redeems
-- Includes instances when the enrolment has been cancelled
CREATE OR REPLACE VIEW Session_Enrolment AS
-- course_id, launch_date, sess_num, sess_date
-- reg_date, credit_card_num, customer_id, cancel_date
-- type ('REGISTER' or 'REDEEM')
    WITH
        _Registers AS 
        (SELECT course_id, launch_date, sess_num,
            sess_date,
            reg_date, 
            credit_card_num, customer_id,
            cancel_date,
            (SELECT 'REGISTER') AS type
        FROM Registers_With_Customers
        ),
        _Redeems AS 
        (SELECT course_id, launch_date, sess_num,
            sess_date,
            redeem_date AS reg_date, 
            credit_card_num, customer_id,
            cancel_date,
            (SELECT 'REDEEM') AS type
        FROM Redeems_With_Customers
        )
    
    SELECT *
    FROM 
        (SELECT *
        FROM _Registers
        UNION
        SELECT *
        FROM _Redeems) AS _
    ORDER BY course_id, launch_date,
        sess_num, customer_id
;

-- For every session, count the number of enrolments that are not cancelled
CREATE OR REPLACE VIEW Not_Cancelled_Enrolment_Count AS
-- course_id, launch_date, sess_num, sess_enrolment
    WITH
    CountEnrolment AS (
        SELECT 
            course_id, launch_date, sess_num,
            COUNT(*) AS sess_enrolment
        FROM Session_Enrolment
        WHERE cancel_date IS NULL
        GROUP BY course_id, launch_date, sess_num
    )
    
    SELECT course_id, launch_date, sess_num,
        COALESCE(C.sess_enrolment, 0) AS sess_enrolment    
    FROM Sessions S
        NATURAL LEFT JOIN CountEnrolment C
    ORDER BY course_id, launch_date, sess_num
;

CREATE OR REPLACE VIEW Offerings_With_Metadata AS
-- course_id, launch_date
-- fees, target_reg, reg_deadline
-- employee_id (admin)
-- course.title, course.duration, course.area_name
-- start_date, end_date, sum_capacity
    WITH
        SessionsGroupByOffering AS (
            SELECT course_id, launch_date,
                MIN(s.sess_date) AS start_date,
                MAX(s.sess_date) AS end_date,
                SUM(v.max_capacity) AS sum_capacity
            FROM Sessions s
                NATURAL JOIN Venues v
            GROUP BY (course_id, launch_date)
        )
    
    SELECT 
        -- Offerings: primary key
        O.course_id, O.launch_date,
        -- Offerings: attributes
        O.fees, O.target_reg, O.reg_deadline,
        -- Offerings: adminstrator
        O.employee_id,
        -- Courses: attributes (joined)
        C.title, C.duration, C.area_name,
        -- Sessions: attribute (joined)
        S.start_date, S.end_date, S.sum_capacity
    FROM ((Offerings O
        NATURAL JOIN Courses C)
        NATURAL LEFT JOIN SessionsGroupByOffering S)
        -- TODO: same issue as Active_Credit_Card
        -- NATURAL LEFT JOIN OR NATURAL JOIN
;

CREATE OR REPLACE VIEW Status_Of_Offerings AS
-- course_id, launch_date
-- fees, target_reg, reg_deadline
-- employee_id (admin)
-- course.title, course.duration, course.area_name
-- start_date, end_date, sum_capacity
-- status
    WITH
        AggEnrolment AS (
            SELECT *,
            -- number of not cancelled registrations
            (SELECT SUM(sess_enrolment)
            FROM Not_Cancelled_Enrolment_Count S
            WHERE S.course_id = O.course_id
                AND S.launch_date = O.launch_date
            ) AS offering_enrolment
            FROM Offerings_With_Metadata O
        )
    
    SELECT *,
        (CASE
            WHEN offering_enrolment < sum_capacity THEN 'AVAILABLE'
            ELSE 'FULLY BOOKED'
        END) AS status
    FROM AggEnrolment
;

-- at most 1 credit card per customer
-- constraint needs to check that active_credit_card is not null
-- also checks that the credit card is still active.
CREATE OR REPLACE VIEW Most_Recent_Credit_Cards_With_Customers AS
-- customer_id, customer_name, credit_card_num, from_date
    SELECT DISTINCT customer_id,
        customer_name,
        credit_card_num,
        expiry_date,
        from_date
    FROM (Customers
        NATURAL JOIN Credit_Cards) CCC
    WHERE from_date = 
        (SELECT MAX(from_date)
        FROM Credit_Cards CC
        WHERE CCC.customer_id = CC.customer_id)
        AND expiry_date > current_date;
;

CREATE OR REPLACE VIEW Num_Remaining_Redemptions AS
-- buy_date, package_id, credit_card_num
-- customer_id
-- max_sess_count
-- raw_redemptions, raw_cancelled, refunded_redemptions
-- remaining_redemptions
    WITH
        AggBuys AS (
            SELECT
                -- Buys: Primary key
                B.buy_date, B.package_id, B.credit_card_num,
                -- Customer information
                C.customer_id,
                -- Max redemption
                Pck.max_sess_count,
                -- Raw number of redemptions 
                (SELECT COUNT(*)
                FROM Redeems_With_Customers R
                WHERE R.buy_date = B.buy_date
                    AND R.package_id = B.package_id
                    AND R.credit_card_num = B.credit_card_num
                ) AS raw_redemptions,
                -- Raw number of cancellation (for fun)
                (SELECT COUNT(*)
                FROM Redeems_With_Customers R
                WHERE R.buy_date = B.buy_date
                    AND R.package_id = B.package_id
                    AND R.credit_card_num = B.credit_card_num
                    AND cancel_date IS NOT NULL
                ) AS raw_cancelled,
                -- Refunded redemptions
                (SELECT COUNT(*)
                FROM Redeems_With_Customers R
                WHERE R.buy_date = B.buy_date
                    AND R.package_id = B.package_id
                    AND R.credit_card_num = B.credit_card_num
                    AND cancel_date IS NOT NULL
                    AND cancel_date + 7 <= sess_date
                ) AS refunded_redemptions
            FROM (Buys B
                NATURAL JOIN Credit_Cards C)
                NATURAL JOIN Course_Packages Pck
        )
        
    SELECT *,
        (A.max_sess_count - A.raw_redemptions
            + A.refunded_redemptions) AS remaining_redemptions
    FROM AggBuys A
;

CREATE OR REPLACE VIEW Package_Status AS
-- buy_date, package_id, credit_card_num,
-- customer_id, status
    SELECT
        -- Buys: primary key
        N.buy_date, N.package_id, N.credit_card_num,
        -- Customer information
        N.customer_id,
        -- Package status
        (CASE
            WHEN N.remaining_redemptions >= 1
                THEN 'ACTIVE'
            WHEN EXISTS (
                SELECT 1
                FROM Redeems_With_Customers R
                WHERE R.customer_id = N.customer_id
                    AND CURRENT_DATE + 7 <= R.sess_date)
                THEN 'PARTIALLY ACTIVE'
            ELSE
                'INACTIVE'
        END) AS status
        FROM Num_Remaining_Redemptions N
;
