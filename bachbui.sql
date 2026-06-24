-- =============================================================================
-- HỆ THỐNG QUẢN LÝ PHÒNG GYM
-- Phân hệ được triển khai:
--   [1] Quản lý Hội viên  (Member, Member_body_perweek)
--   [2] Dịch vụ & Đăng ký (Service, Package, Class, Enroll)
--   [5] HLV & Lớp học     (Class, Coach_Checkin, Employee[job_id='C'])
-- =============================================================================

-- =============================================================================
-- PHẦN 1: PHÂN HỆ QUẢN LÝ HỘI VIÊN
-- =============================================================================

-- [1.1] Đăng ký hội viên mới
CREATE OR REPLACE FUNCTION register_member(
    p_first_name   VARCHAR(50),
    p_last_name    VARCHAR(50),
    p_email        VARCHAR(100),
    p_phone_number VARCHAR(20)
) RETURNS INT AS $$
DECLARE
v_member_id INT;
BEGIN

    IF EXISTS (SELECT 1 FROM Member WHERE email = p_email AND is_deleted = FALSE) THEN
        RAISE EXCEPTION 'EMAIL_EXISTS: Email % đã được đăng ký.', p_email;
END IF;

INSERT INTO Member (first_name, last_name, email, phone_number)
VALUES (p_first_name, p_last_name, p_email, p_phone_number)
    RETURNING member_id INTO v_member_id;

RETURN v_member_id;
END;
$$ LANGUAGE plpgsql;


-- [1.2] Cập nhật thông tin hội viên
CREATE OR REPLACE PROCEDURE update_member(
    p_member_id    INT,
    p_first_name   VARCHAR(50)  DEFAULT NULL,
    p_last_name    VARCHAR(50)  DEFAULT NULL,
    p_email        VARCHAR(100) DEFAULT NULL,
    p_phone_number VARCHAR(20)  DEFAULT NULL
) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Member WHERE member_id = p_member_id AND is_deleted = FALSE) THEN
        RAISE EXCEPTION 'MEMBER_NOT_FOUND: Không tìm thấy hội viên ID = %', p_member_id;
END IF;

    IF p_email IS NOT NULL AND EXISTS (
        SELECT 1 FROM Member WHERE email = p_email AND member_id <> p_member_id AND is_deleted = FALSE
    ) THEN
        RAISE EXCEPTION 'EMAIL_EXISTS: Email % đã được sử dụng bởi hội viên khác.', p_email;
END IF;

UPDATE Member SET
                  first_name   = COALESCE(p_first_name,   first_name),
                  last_name    = COALESCE(p_last_name,    last_name),
                  email        = COALESCE(p_email,        email),
                  phone_number = COALESCE(p_phone_number, phone_number)
WHERE member_id = p_member_id;
END;
$$ LANGUAGE plpgsql;


-- [1.3] Tìm kiếm hội viên
CREATE OR REPLACE FUNCTION search_members(
    p_keyword VARCHAR(100)
) RETURNS TABLE (
    member_id    INT,
    full_name    TEXT,
    email        VARCHAR(100),
    phone_number VARCHAR(20)
) AS $$
BEGIN
RETURN QUERY
SELECT
    m.member_id,
    (m.first_name || ' ' || m.last_name)::TEXT AS full_name,
    m.email,
    m.phone_number
FROM Member m
WHERE m.is_deleted = FALSE
  AND (m.first_name   ILIKE '%' || p_keyword || '%'
          OR m.last_name ILIKE '%' || p_keyword || '%'
          OR m.email     ILIKE '%' || p_keyword || '%')
ORDER BY m.last_name, m.first_name;
END;
$$ LANGUAGE plpgsql;


-- [1.4] Xem thông tin chi tiết một hội viên
CREATE OR REPLACE FUNCTION get_member_detail(
    p_member_id INT
) RETURNS TABLE (
    member_id        INT,
    full_name        TEXT,
    email            VARCHAR(100),
    phone_number     VARCHAR(20),
    total_enrollments BIGINT,
    active_enrollments BIGINT
) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Member WHERE member_id = p_member_id AND is_deleted = FALSE) THEN
        RAISE EXCEPTION 'MEMBER_NOT_FOUND: Không tìm thấy hội viên ID = %', p_member_id;
END IF;

RETURN QUERY
SELECT
    m.member_id,
    (m.first_name || ' ' || m.last_name)::TEXT AS full_name,
    m.email,
    m.phone_number,
    COUNT(e.enroll_id)                                               AS total_enrollments,
    COUNT(e.enroll_id) FILTER (WHERE e.status = 'active')           AS active_enrollments
FROM Member m
         LEFT JOIN Enroll e ON e.member_id = m.member_id
WHERE m.member_id = p_member_id
GROUP BY m.member_id, m.first_name, m.last_name, m.email, m.phone_number;
END;
$$ LANGUAGE plpgsql;


-- [1.5] Ghi nhận chỉ số cơ thể theo tuần
CREATE OR REPLACE PROCEDURE record_body_stats(
    p_member_id   INT,
    p_week        INT,
    p_date        DATE,
    p_body_fat    DECIMAL(5,2),
    p_muscle_mass DECIMAL(5,2)
) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Member WHERE member_id = p_member_id AND is_deleted = FALSE) THEN
        RAISE EXCEPTION 'MEMBER_NOT_FOUND: Không tìm thấy hội viên ID = %', p_member_id;
END IF;

    IF p_body_fat < 0 OR p_body_fat > 100 THEN
        RAISE EXCEPTION 'INVALID_BODY_FAT: Giá trị mỡ cơ thể phải từ 0 đến 100, nhận được %', p_body_fat;
END IF;

INSERT INTO Member_body_perweek (member_id, week, date, body_fat, muscle_mass)
VALUES (p_member_id, p_week, p_date, p_body_fat, p_muscle_mass)
    ON CONFLICT (member_id, week)
    DO UPDATE SET
               date        = EXCLUDED.date,
               body_fat    = EXCLUDED.body_fat,
               muscle_mass = EXCLUDED.muscle_mass;
END;
$$ LANGUAGE plpgsql;


-- [1.6] Xem lịch sử chỉ số cơ thể
CREATE OR REPLACE FUNCTION get_body_history(
    p_member_id   INT,
    p_limit_weeks INT DEFAULT 12
) RETURNS TABLE (
    week        INT,
    record_date DATE,
    body_fat    DECIMAL(5,2),
    muscle_mass DECIMAL(5,2)
) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Member WHERE member_id = p_member_id AND is_deleted = FALSE) THEN
        RAISE EXCEPTION 'MEMBER_NOT_FOUND: Không tìm thấy hội viên ID = %', p_member_id;
END IF;

RETURN QUERY
SELECT
    b.week,
    b.date       AS record_date,
    b.body_fat,
    b.muscle_mass
FROM Member_body_perweek b
WHERE b.member_id = p_member_id
ORDER BY b.week DESC
    LIMIT p_limit_weeks;
END;
$$ LANGUAGE plpgsql;


-- [1.7] So sánh chỉ số cơ thể
CREATE OR REPLACE FUNCTION compare_body_stats(
    p_member_id INT,
    p_week      INT
) RETURNS TABLE (
    current_week   INT,
    current_fat    DECIMAL(5,2),
    current_muscle DECIMAL(5,2),
    prev_week      INT,
    prev_fat       DECIMAL(5,2),
    prev_muscle    DECIMAL(5,2),
    delta_fat      DECIMAL(5,2),
    delta_muscle   DECIMAL(5,2)
) AS $$
BEGIN
RETURN QUERY
    WITH current_w AS (
        SELECT b.week, b.body_fat, b.muscle_mass
        FROM Member_body_perweek b
        WHERE b.member_id = p_member_id AND b.week = p_week
    ),
    prev_w AS (
        SELECT b.week, b.body_fat, b.muscle_mass
        FROM Member_body_perweek b
        WHERE b.member_id = p_member_id AND b.week < p_week
        ORDER BY b.week DESC
        LIMIT 1
    )
SELECT
    c.week                         AS current_week,
    c.body_fat                     AS current_fat,
    c.muscle_mass                  AS current_muscle,
    p.week                         AS prev_week,
    p.body_fat                     AS prev_fat,
    p.muscle_mass                  AS prev_muscle,
    (c.body_fat    - p.body_fat)   AS delta_fat,
    (c.muscle_mass - p.muscle_mass)AS delta_muscle
FROM current_w c
         LEFT JOIN prev_w p ON TRUE;
END;
$$ LANGUAGE plpgsql;


-- [1.8] Xóa mềm hội viên
ALTER TABLE Member ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE;
CREATE OR REPLACE PROCEDURE delete_member(
    p_member_id INT
) AS $$
DECLARE
v_active_count INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Member WHERE member_id = p_member_id AND is_deleted = FALSE) THEN
        RAISE EXCEPTION 'MEMBER_NOT_FOUND: Không tìm thấy hội viên ID = %.', p_member_id;
END IF;

SELECT COUNT(*) INTO v_active_count
FROM Enroll
WHERE member_id = p_member_id AND status = 'active';

IF v_active_count > 0 THEN
        RAISE EXCEPTION 'HAS_ACTIVE_ENROLL: Hội viên ID = % còn % đăng ký đang active. Hủy hoặc chờ hết hạn trước khi xóa.',
            p_member_id, v_active_count;
END IF;

UPDATE Member SET is_deleted = TRUE WHERE member_id = p_member_id;

DELETE FROM Member_body_perweek WHERE member_id = p_member_id;
UPDATE Enroll SET status = 'inactive' WHERE member_id = p_member_id;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- PHẦN 2: PHÂN HỆ DỊCH VỤ & ĐĂNG KÝ
-- =============================================================================

-- [2.1] Tạo gói tập mới (Package)
CREATE OR REPLACE FUNCTION create_package(
    p_service_name    VARCHAR(255),
    p_price           DECIMAL(10,2),
    p_duration_months INT,
    p_room_id         INT          DEFAULT NULL,
    p_information     VARCHAR(50)  DEFAULT NULL
) RETURNS INT AS $$
DECLARE
v_service_id INT;
BEGIN
    IF p_room_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Room WHERE room_id = p_room_id) THEN
        RAISE EXCEPTION 'ROOM_NOT_FOUND: Không tìm thấy phòng ID = %', p_room_id;
END IF;

INSERT INTO Service (service_name, price, service_type)
VALUES (p_service_name, p_price, 'PACKAGE')
    RETURNING service_id INTO v_service_id;

INSERT INTO Package (service_id, duration_in_months, information, room_id)
VALUES (v_service_id, p_duration_months, p_information, p_room_id);

RETURN v_service_id;
END;
$$ LANGUAGE plpgsql;


-- [2.2] Tạo lớp học mới (Class)
CREATE OR REPLACE FUNCTION create_class(
    p_service_name    VARCHAR(255),
    p_price           DECIMAL(10,2),
    p_max_students    INT,
    p_duration_months INT,
    p_time_begin      TIME,
    p_room_id         INT         DEFAULT NULL,
    p_information     VARCHAR(50) DEFAULT NULL
) RETURNS INT AS $$
DECLARE
v_class_id INT;
BEGIN
    IF p_max_students <= 0 THEN
        RAISE EXCEPTION 'INVALID_MAX_STUDENTS: Sĩ số tối đa phải lớn hơn 0, nhận được %', p_max_students;
END IF;

    IF p_room_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Room WHERE room_id = p_room_id) THEN
        RAISE EXCEPTION 'ROOM_NOT_FOUND: Không tìm thấy phòng ID = %', p_room_id;
END IF;

INSERT INTO Service (service_name, price, service_type)
VALUES (p_service_name, p_price, 'CLASS')
    RETURNING service_id INTO v_class_id;

INSERT INTO Class (class_id, maximum_students, information, time_begin, duration_in_months, room_id)
VALUES (v_class_id, p_max_students, p_information, p_time_begin, p_duration_months, p_room_id);

RETURN v_class_id;
END;
$$ LANGUAGE plpgsql;


-- [2.3] Cập nhật giá dịch vụ
CREATE OR REPLACE PROCEDURE update_service_price(
    p_service_id INT,
    p_new_price  DECIMAL(10,2)
) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Service WHERE service_id = p_service_id) THEN
        RAISE EXCEPTION 'SERVICE_NOT_FOUND: Không tìm thấy dịch vụ ID = %', p_service_id;
END IF;

    IF p_new_price <= 0 THEN
        RAISE EXCEPTION 'INVALID_PRICE: Giá dịch vụ phải lớn hơn 0, nhận được %', p_new_price;
END IF;

UPDATE Service SET price = p_new_price WHERE service_id = p_service_id;
END;
$$ LANGUAGE plpgsql;


-- [2.4] Liệt kê tất cả dịch vụ
CREATE OR REPLACE FUNCTION list_services(
    p_type_filter VARCHAR(50) DEFAULT NULL
) RETURNS TABLE (
    service_id        INT,
    service_name      VARCHAR(255),
    service_type      VARCHAR(50),
    price             DECIMAL(10,2),
    duration_months   INT,
    max_students      INT,
    time_begin        TIME,
    time_end          TIME,
    room_id           INT,
    information       VARCHAR(50)
) AS $$
BEGIN
RETURN QUERY
SELECT
    s.service_id,
    s.service_name,
    s.service_type,
    s.price,
    COALESCE(pk.duration_in_months, cl.duration_in_months) AS duration_months,
    cl.maximum_students                                     AS max_students,
    cl.time_begin,
    cl.time_end,
    COALESCE(pk.room_id, cl.room_id)                       AS room_id,
    COALESCE(pk.information, cl.information)               AS information
FROM Service s
         LEFT JOIN Package pk ON pk.service_id = s.service_id
         LEFT JOIN Class   cl ON cl.class_id   = s.service_id
WHERE (p_type_filter IS NULL OR s.service_type = p_type_filter)
ORDER BY s.service_type, s.service_name;
END;
$$ LANGUAGE plpgsql;


-- [2.5] Đăng ký dịch vụ cho hội viên (Hỗ trợ nối tiếp hạn thẻ)
CREATE OR REPLACE FUNCTION enroll_member(
    p_member_id  INT,
    p_service_id INT,
    p_start_date DATE DEFAULT CURRENT_DATE
) RETURNS INT AS $$
DECLARE
v_enroll_id             INT;
    v_service_type          VARCHAR(50);
    v_duration              INT;
    v_max_students          INT;
    v_current_count         INT;
    v_calculated_start_date DATE := p_start_date;
    v_existing_end_date     DATE;
    v_end_date              DATE;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Member WHERE member_id = p_member_id AND is_deleted = FALSE) THEN
        RAISE EXCEPTION 'MEMBER_NOT_FOUND: Không tìm thấy hội viên ID = %', p_member_id;
END IF;

SELECT s.service_type INTO v_service_type
FROM Service s WHERE s.service_id = p_service_id;

IF NOT FOUND THEN
        RAISE EXCEPTION 'SERVICE_NOT_FOUND: Không tìm thấy dịch vụ ID = %', p_service_id;
END IF;

SELECT end_date INTO v_existing_end_date
FROM Enroll
WHERE member_id = p_member_id AND service_id = p_service_id AND status = 'active';

IF v_existing_end_date IS NOT NULL THEN
        v_calculated_start_date := v_existing_end_date + 1;
END IF;

    IF v_service_type = 'PACKAGE' THEN
SELECT pk.duration_in_months INTO v_duration
FROM Package pk WHERE pk.service_id = p_service_id;

ELSIF v_service_type = 'CLASS' THEN
SELECT cl.duration_in_months, cl.maximum_students
INTO v_duration, v_max_students
FROM Class cl WHERE cl.class_id = p_service_id;

SELECT COUNT(*) INTO v_current_count
FROM Enroll
WHERE service_id = p_service_id AND status = 'active';

IF v_current_count >= v_max_students THEN
            RAISE EXCEPTION 'CLASS_FULL: Lớp ID = % đã đủ % học viên.', p_service_id, v_max_students;
END IF;
END IF;

    v_end_date := (v_calculated_start_date + (v_duration || ' months')::INTERVAL)::DATE;

INSERT INTO Enroll (member_id, service_id, start_date, end_date, status)
VALUES (p_member_id, p_service_id, v_calculated_start_date, v_end_date, 'active')
    RETURNING enroll_id INTO v_enroll_id;

RETURN v_enroll_id;
END;
$$ LANGUAGE plpgsql;


-- [2.6] Đóng băng / hủy đăng ký (Cộng dồn ngày đóng băng khi kích hoạt lại)
ALTER TABLE Enroll ADD COLUMN IF NOT EXISTS freeze_start_date DATE DEFAULT NULL;
CREATE OR REPLACE PROCEDURE change_enroll_status(
    p_enroll_id  INT,
    p_new_status VARCHAR(20)
) AS $$
DECLARE
v_current_status VARCHAR(20);
v_freeze_start DATE;
v_freeze_days INT;
BEGIN
SELECT status, freeze_start_date INTO v_current_status, v_freeze_start
FROM Enroll WHERE enroll_id = p_enroll_id;

IF NOT FOUND THEN
        RAISE EXCEPTION 'ENROLL_NOT_FOUND: Không tìm thấy đăng ký ID = %', p_enroll_id;
END IF;

    IF v_current_status = 'inactive' THEN
        RAISE EXCEPTION 'INVALID_TRANSITION: Đăng ký ID = % đã inactive, không thể chuyển sang "%".', p_enroll_id, p_new_status;
END IF;

    IF v_current_status = p_new_status THEN
        RETURN;
END IF;

    IF v_current_status = 'active' AND p_new_status = 'frozen' THEN
UPDATE Enroll
SET status = p_new_status,
    freeze_start_date = CURRENT_DATE
WHERE enroll_id = p_enroll_id;

ELSIF v_current_status = 'frozen' AND p_new_status = 'active' THEN
        v_freeze_days := (CURRENT_DATE - v_freeze_start);

UPDATE Enroll
SET status = p_new_status,
    end_date = end_date + (v_freeze_days || ' days')::INTERVAL,
            freeze_start_date = NULL
WHERE enroll_id = p_enroll_id;

ELSE
UPDATE Enroll SET status = p_new_status, freeze_start_date = NULL WHERE enroll_id = p_enroll_id;
END IF;
END;
$$ LANGUAGE plpgsql;


-- [2.7] Xem danh sách đăng ký của một hội viên
CREATE OR REPLACE FUNCTION get_member_enrollments(
    p_member_id    INT,
    p_status_filter VARCHAR(20) DEFAULT NULL
) RETURNS TABLE (
    enroll_id    INT,
    service_id   INT,
    service_name VARCHAR(255),
    service_type VARCHAR(50),
    start_date   DATE,
    end_date     DATE,
    status       VARCHAR(20),
    days_left    INT
) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Member WHERE member_id = p_member_id AND is_deleted = FALSE) THEN
        RAISE EXCEPTION 'MEMBER_NOT_FOUND: Không tìm thấy hội viên ID = %', p_member_id;
END IF;

RETURN QUERY
SELECT
    e.enroll_id,
    s.service_id,
    s.service_name,
    s.service_type,
    e.start_date,
    e.end_date,
    e.status,
    (e.end_date - CURRENT_DATE)::INT AS days_left
FROM Enroll e
         JOIN Service s ON s.service_id = e.service_id
WHERE e.member_id = p_member_id
  AND (p_status_filter IS NULL OR e.status = p_status_filter)
ORDER BY e.start_date DESC;
END;
$$ LANGUAGE plpgsql;


-- [2.8] Tự động hết hạn các enroll quá ngày end_date
CREATE OR REPLACE FUNCTION expire_enrollments()
RETURNS INT AS $$
DECLARE
v_count INT;
BEGIN
UPDATE Enroll
SET status = 'inactive'
WHERE status = 'active'
  AND end_date < CURRENT_DATE;

GET DIAGNOSTICS v_count = ROW_COUNT;
RETURN v_count;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- PHẦN 5: PHÂN HỆ HLV & LỚP HỌC
-- =============================================================================

-- [5.1] Lấy danh sách HLV
CREATE OR REPLACE FUNCTION list_coaches()
RETURNS TABLE (
    employee_id      INT,
    full_name        TEXT,
    phone_number     VARCHAR(20),
    salary           DECIMAL(12,2),
    salary_af_tariff DECIMAL(12,2),
    classes_teaching BIGINT
) AS $$
BEGIN
RETURN QUERY
SELECT
    e.employee_id,
    (e.first_name || ' ' || e.last_name)::TEXT AS full_name,
    e.phone_number,
    e.salary,
    e.salary_af_tariff,
    COUNT(DISTINCT cc.class_id) AS classes_teaching
FROM Employee e
         LEFT JOIN Coach_Checkin cc ON cc.coach_id = e.employee_id
WHERE e.job_id = 'C'
GROUP BY e.employee_id, e.first_name, e.last_name,
         e.phone_number, e.salary, e.salary_af_tariff
ORDER BY e.last_name, e.first_name;
END;
$$ LANGUAGE plpgsql;


-- [5.2] Điểm danh HLV cho một buổi dạy
ALTER TABLE Coach_Checkin DROP CONSTRAINT IF EXISTS coach_checkin_pkey;
ALTER TABLE Coach_Checkin ADD PRIMARY KEY (coach_id, class_id, date);

CREATE OR REPLACE PROCEDURE coach_checkin(
    p_coach_id INT,
    p_class_id INT,
    p_date     DATE,
    p_present  VARCHAR(20)
) AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM Employee WHERE employee_id = p_coach_id AND job_id = 'C'
    ) THEN
        RAISE EXCEPTION 'COACH_NOT_FOUND: Không tìm thấy HLV ID = % (hoặc không phải Coach)', p_coach_id;
END IF;

    IF NOT EXISTS (SELECT 1 FROM Class WHERE class_id = p_class_id) THEN
        RAISE EXCEPTION 'CLASS_NOT_FOUND: Không tìm thấy lớp học ID = %', p_class_id;
END IF;

    IF p_present NOT IN ('yes', 'absent', 'execute_absent') THEN
        RAISE EXCEPTION 'INVALID_STATUS: Trạng thái "%" không hợp lệ. Dùng: yes | absent | execute_absent', p_present;
END IF;

    IF EXISTS (
        SELECT 1 FROM Coach_Checkin
        WHERE coach_id = p_coach_id AND class_id = p_class_id AND date = p_date
    ) THEN
        RAISE EXCEPTION 'ALREADY_CHECKED_IN: HLV % đã có bản ghi cho lớp % vào ngày %. Dùng update_coach_checkin() để thay đổi.', p_coach_id, p_class_id, p_date;
END IF;

INSERT INTO Coach_Checkin (coach_id, class_id, date, present)
VALUES (p_coach_id, p_class_id, p_date, p_present);
END;
$$ LANGUAGE plpgsql;


-- [5.3] Cập nhật điểm danh HLV
CREATE OR REPLACE PROCEDURE update_coach_checkin(
    p_coach_id    INT,
    p_class_id    INT,
    p_target_date DATE,
    p_new_date    DATE        DEFAULT NULL,
    p_present     VARCHAR(20) DEFAULT NULL
) AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM Coach_Checkin WHERE coach_id = p_coach_id AND class_id = p_class_id AND date = p_target_date
    ) THEN
        RAISE EXCEPTION 'CHECKIN_NOT_FOUND: Chưa có bản ghi điểm danh HLV % lớp % vào ngày %.', p_coach_id, p_class_id, p_target_date;
END IF;

    IF p_present IS NOT NULL AND p_present NOT IN ('yes', 'absent', 'execute_absent') THEN
        RAISE EXCEPTION 'INVALID_STATUS: Trạng thái "%" không hợp lệ.', p_present;
END IF;

UPDATE Coach_Checkin
SET
    date    = COALESCE(p_new_date, date),
    present = COALESCE(p_present,  present)
WHERE coach_id = p_coach_id AND class_id = p_class_id AND date = p_target_date;
END;
$$ LANGUAGE plpgsql;


-- [5.4] Xem lịch sử điểm danh của một HLV
CREATE OR REPLACE FUNCTION get_coach_checkin_history(
    p_coach_id       INT,
    p_present_filter VARCHAR(20) DEFAULT NULL
) RETURNS TABLE (
    class_id     INT,
    class_name   VARCHAR(255),
    checkin_date DATE,
    present      VARCHAR(20)
) AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM Employee WHERE employee_id = p_coach_id AND job_id = 'C'
    ) THEN
        RAISE EXCEPTION 'COACH_NOT_FOUND: Không tìm thấy HLV ID = %', p_coach_id;
END IF;

RETURN QUERY
SELECT
    cc.class_id,
    s.service_name   AS class_name,
    cc.date          AS checkin_date,
    cc.present
FROM Coach_Checkin cc
         JOIN Service s ON s.service_id = cc.class_id
WHERE cc.coach_id = p_coach_id
  AND (p_present_filter IS NULL OR cc.present = p_present_filter)
ORDER BY cc.date DESC;
END;
$$ LANGUAGE plpgsql;


-- [5.5] Thống kê tỷ lệ có mặt của HLV (theo lớp)
CREATE OR REPLACE FUNCTION coach_attendance_stats(
    p_coach_id INT DEFAULT NULL
) RETURNS TABLE (
    coach_id          INT,
    coach_name        TEXT,
    class_id          INT,
    class_name        VARCHAR(255),
    total_sessions    BIGINT,
    present_count     BIGINT,
    absent_count      BIGINT,
    exec_absent_count BIGINT,
    attendance_rate   NUMERIC(5,2)
) AS $$
BEGIN
RETURN QUERY
SELECT
    e.employee_id                                               AS coach_id,
    (e.first_name || ' ' || e.last_name)::TEXT                 AS coach_name,
    cc.class_id,
    s.service_name                                             AS class_name,
    COUNT(*)                                                   AS total_sessions,
    COUNT(*) FILTER (WHERE cc.present = 'yes')                AS present_count,
    COUNT(*) FILTER (WHERE cc.present = 'absent')             AS absent_count,
    COUNT(*) FILTER (WHERE cc.present = 'execute_absent')     AS exec_absent_count,
    ROUND(
            COUNT(*) FILTER (WHERE cc.present = 'yes') * 100.0
                / NULLIF(COUNT(*), 0)
        , 2)                                                       AS attendance_rate
FROM Coach_Checkin cc
         JOIN Employee e ON e.employee_id = cc.coach_id
         JOIN Service  s ON s.service_id  = cc.class_id
WHERE (p_coach_id IS NULL OR cc.coach_id = p_coach_id)
GROUP BY e.employee_id, e.first_name, e.last_name, cc.class_id, s.service_name
ORDER BY coach_name, class_name;
END;
$$ LANGUAGE plpgsql;


-- [5.6] Xem danh sách học viên đang active trong một lớp
CREATE OR REPLACE FUNCTION get_class_students(
    p_class_id INT
) RETURNS TABLE (
    member_id    INT,
    full_name    TEXT,
    email        VARCHAR(100),
    phone_number VARCHAR(20),
    enroll_date  DATE,
    end_date     DATE
) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Class WHERE class_id = p_class_id) THEN
        RAISE EXCEPTION 'CLASS_NOT_FOUND: Không tìm thấy lớp học ID = %', p_class_id;
END IF;

RETURN QUERY
SELECT
    m.member_id,
    (m.first_name || ' ' || m.last_name)::TEXT AS full_name,
    m.email,
    m.phone_number,
    e.start_date AS enroll_date,
    e.end_date
FROM Enroll e
         JOIN Member m ON m.member_id = e.member_id
WHERE e.service_id = p_class_id
  AND e.status = 'active'
  AND m.is_deleted = FALSE
ORDER BY m.last_name, m.first_name;
END;
$$ LANGUAGE plpgsql;


-- [5.7] Xem lịch dạy của một HLV (Tránh lỗi nhân bản sĩ số bằng DISTINCT)
CREATE OR REPLACE FUNCTION get_coach_schedule(
    p_coach_id INT
) RETURNS TABLE (
    class_id      INT,
    class_name    VARCHAR(255),
    time_begin    TIME,
    time_end      TIME,
    room_id       INT,
    active_students BIGINT,
    max_students    INT
) AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM Employee WHERE employee_id = p_coach_id AND job_id = 'C'
    ) THEN
        RAISE EXCEPTION 'COACH_NOT_FOUND: Không tìm thấy HLV ID = %', p_coach_id;
END IF;

RETURN QUERY
SELECT
    cl.class_id,
    s.service_name       AS class_name,
    cl.time_begin,
    cl.time_end,
    cl.room_id,
    COUNT(DISTINCT e.enroll_id)   AS active_students,
    cl.maximum_students  AS max_students
FROM Coach_Checkin cc
         JOIN Class   cl ON cl.class_id   = cc.class_id
         JOIN Service s  ON s.service_id  = cl.class_id
         LEFT JOIN Enroll e ON e.service_id = cl.class_id AND e.status = 'active'
WHERE cc.coach_id = p_coach_id
GROUP BY cl.class_id, s.service_name, cl.time_begin, cl.time_end,
         cl.room_id, cl.maximum_students
ORDER BY cl.time_begin;
END;
$$ LANGUAGE plpgsql;


-- [5.8] Cảnh báo lớp có HLV vắng mặt không phép nhiều
CREATE OR REPLACE FUNCTION get_absent_warnings(
    p_threshold INT DEFAULT 3
) RETURNS TABLE (
    coach_id       INT,
    coach_name     TEXT,
    class_id       INT,
    class_name     VARCHAR(255),
    absent_count   BIGINT
) AS $$
BEGIN
RETURN QUERY
SELECT
    e.employee_id                                AS coach_id,
    (e.first_name || ' ' || e.last_name)::TEXT  AS coach_name,
    cc.class_id,
    s.service_name                              AS class_name,
    COUNT(*) FILTER (WHERE cc.present = 'absent') AS absent_count
FROM Coach_Checkin cc
         JOIN Employee e ON e.employee_id = cc.coach_id
         JOIN Service  s ON s.service_id  = cc.class_id
GROUP BY e.employee_id, e.first_name, e.last_name, cc.class_id, s.service_name
HAVING COUNT(*) FILTER (WHERE cc.present = 'absent') >= p_threshold
ORDER BY absent_count DESC;
END;
$$ LANGUAGE plpgsql;