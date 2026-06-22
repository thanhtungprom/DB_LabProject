--  Lệnh 1:  TRIGGER: Ngăn chặn việc đăng ký quá sĩ số (Overbooking)
CREATE OR REPLACE FUNCTION check_class_capacity()
RETURNS TRIGGER AS $$
DECLARE
    v_max_students INT;
    v_current_enrolled INT;
BEGIN
    -- Kiểm tra xem service_id này có phải là Class không, lấy max_students
    SELECT maximum_students INTO v_max_students 
    FROM Class WHERE class_id = NEW.service_id;

    IF FOUND THEN
        -- Đếm số lượng học viên đang active của lớp này
        SELECT COUNT(*) INTO v_current_enrolled 
        FROM Enroll 
        WHERE service_id = NEW.service_id ;

        IF v_current_enrolled >= v_max_students THEN
            RAISE EXCEPTION 'Lớp học đã đạt sĩ số tối đa (%). Không thể đăng ký thêm!', v_max_students;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_class_capacity
BEFORE INSERT OR UPDATE ON Enroll
FOR EACH ROW EXECUTE FUNCTION check_class_capacity();