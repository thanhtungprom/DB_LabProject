--  Lệnh 1:  TRIGGER: Ngăn chặn việc đăng ký quá sĩ số (Overbooking)
CREATE OR REPLACE FUNCTION check_class_capacity()
RETURNS TRIGGER AS $$
DECLARE
    v_max_students INT;
    v_current_enrolled INT;
BEGIN
    -- Kiểm tra xem service_id này có phải là Class không, lấy max_students
    SELECT maximum_students INTO v_max_students 
    FROM Class WHERE class_id = NEW.service_id AND status <> 'inactive';

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

--  Lệnh 2  Đăng ký dịch vụ & Tự động tạo Hóa đơn
CREATE OR REPLACE FUNCTION fn_register_service(
    p_service_id INT, 
    p_staff_id INT,
    -- Truyền ID nếu là khách cũ, truyền NULL nếu là khách mới
    p_member_id INT DEFAULT NULL, 
    -- Các thông tin dưới đây chỉ bắt buộc nhập khi là khách mới
    p_first_name VARCHAR DEFAULT NULL,
    p_last_name VARCHAR DEFAULT NULL,
    p_phone VARCHAR DEFAULT NULL,
    p_email VARCHAR DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
    v_price DECIMAL(10,2);
    v_duration INT;
    v_end_date DATE;
    v_payment_id INT;
    v_final_member_id INT;
    v_service_type VARCHAR(50);
BEGIN
    -- ==========================================
    -- 1. XỬ LÝ KHÁCH HÀNG
    -- ==========================================
    IF p_member_id IS NULL THEN
        -- Lệnh RETURNING sẽ lấy ngay cái ID vừa tự sinh đó gán vào biến v_final_member_id
        INSERT INTO Member (first_name, last_name, phone_number, email)
        VALUES (p_first_name, p_last_name, p_phone, p_email)
        RETURNING member_id INTO v_final_member_id;
    ELSE
        v_final_member_id := p_member_id;
    END IF;

    -- ==========================================
    -- 2. LẤY GIÁ VÀ TÍNH NGÀY KẾT THÚC
    -- ==========================================
    -- Lấy giá và loại dịch vụ
    SELECT price, service_type INTO v_price, v_service_type 
    FROM Service 
    WHERE service_id = p_service_id;

    -- Tìm thời hạn (duration_in_months) tùy theo nó là Gói tập hay Lớp học
    IF v_service_type = 'PACKAGE' THEN
        SELECT duration_in_months INTO v_duration FROM Package WHERE service_id = p_service_id;
    ELSE
        SELECT duration_in_months INTO v_duration FROM Class WHERE class_id = p_service_id;
    END IF;

    -- Tính ngày kết thúc bằng cách lấy ngày hôm nay cộng thêm số tháng
    v_end_date := CURRENT_DATE + (v_duration || ' months')::INTERVAL;

    -- ==========================================
    -- 3. GHI NHẬN ĐĂNG KÝ VÀ LẬP HÓA ĐƠN
    -- ==========================================
    -- Thêm vào Enroll
    INSERT INTO Enroll (member_id, service_id, start_date, end_date, status)
    VALUES (v_final_member_id, p_service_id, CURRENT_DATE, v_end_date, 'active');

    -- Thêm vào Payment và lấy ra payment_id vừa tạo
    INSERT INTO Payment (member_id, staff_id, date, time, service_id, total_price)
    VALUES (v_final_member_id, p_staff_id, CURRENT_DATE, CURRENT_TIME, p_service_id, v_price)
    RETURNING payment_id INTO v_payment_id;

    -- Thêm vào chi tiết hóa đơn
    INSERT INTO Payment_detail (payment_id, service_id, unit_price)
    VALUES (v_payment_id, p_service_id, v_price);

END;
$$ LANGUAGE plpgsql;

--  Lệnh 3: Tự động cập nhật trạng thái Thiết bị sau khi Sửa chữa
CREATE OR REPLACE FUNCTION update_device_after_repair()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'completed' AND OLD.status = 'pending' THEN
        UPDATE Device
        SET status = 'Available',
            next_maintenance = CURRENT_DATE + 90
        WHERE device_id = NEW.device_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_after_repair_complete
AFTER UPDATE OF status ON Repair
FOR EACH ROW EXECUTE FUNCTION update_device_after_repair();

--  Lệnh 4: Xếp hạng sự tiến bộ của Hội viên
SELECT 
    t1.member_id,
    t1.week,
    t1.date,
    t1.body_fat AS current_week_fat,
    t2.body_fat AS previous_week_fat,
    (t1.body_fat - t2.body_fat) AS fat_change
FROM Member_body_perweek t1
LEFT JOIN Member_body_perweek t2 
       ON t1.member_id = t2.member_id 
      AND t1.week = t2.week + 1
ORDER BY t1.member_id, t1.week;

-- Lệnh 5: Báo cáo Lợi nhuận (P&L) theo Tháng
WITH Revenue AS (
    SELECT COALESCE(SUM(total_price), 0) as total_revenue
    FROM Payment
    WHERE EXTRACT(MONTH FROM date) = EXTRACT(MONTH FROM CURRENT_DATE)
),
Expenses AS (
    SELECT 
        (SELECT COALESCE(SUM(total_cost), 0) FROM Fee WHERE EXTRACT(MONTH FROM pay_date) = EXTRACT(MONTH FROM CURRENT_DATE)) +
        (SELECT COALESCE(SUM(payment), 0) FROM Repair WHERE status = 'completed' AND EXTRACT(MONTH FROM repair_date) = EXTRACT(MONTH FROM CURRENT_DATE))
        AS total_expense
)
SELECT 
    r.total_revenue,
    e.total_expense,
    (r.total_revenue - e.total_expense) AS net_profit
FROM Revenue r, Expenses e;


--  Lệnh 6: Tối ưu hóa truy vấn bằng index
-- Tăng tốc độ tìm kiếm khách hàng đang active
CREATE INDEX idx_enroll_status ON Enroll(member_id, status);

-- Tăng tốc độ lọc doanh thu theo thời gian
CREATE INDEX idx_payment_date ON Payment(date DESC);

-- Tăng tốc độ truy xuất các thiết bị cần bảo trì
CREATE INDEX idx_device_maintenance ON Device(status, next_maintenance);

--Lệnh 7:  Tìm Khách hàng "Sắp rời bỏ"
SELECT 
    m.member_id, 
    m.first_name, 
    m.last_name, 
    m.phone_number,
    e.end_date AS last_expired_date
FROM Member m
JOIN Enroll e ON m.member_id = e.member_id
WHERE e.end_date < CURRENT_DATE
  AND NOT EXISTS (
      -- Kiểm tra xem từ lúc hết hạn đến nay khách có mua thêm gì không
      SELECT 1 
      FROM Payment p 
      WHERE p.member_id = m.member_id 
        AND p.date > e.end_date
  );

  --Lệnh 8: Lọc danh sách các Lớp học (Class) có sĩ số lớn
SELECT 
    s.service_name, 
    c.time_begin, 
    c.time_end, 
    c.maximum_students
FROM Service s
JOIN Class c ON s.service_id = c.class_id
WHERE c.maximum_students >= 20
ORDER BY c.time_begin ASC;

--Lệnh 9: Thống kê số lượng thiết bị đang không thể sử dụng theo từng phòng
SELECT 
    room_id, 
    COUNT(device_id) AS total_broken_devices
FROM Device
WHERE status <> 'Available'
GROUP BY room_id
ORDER BY total_broken_devices DESC;

-- Lệnh 10: Lọc danh sách Hội viên chưa từng đăng ký bất kỳ dịch vụ nào
SELECT 
    m.member_id, 
    m.first_name, 
    m.last_name, 
    m.phone_number
FROM Member m
LEFT JOIN Enroll e ON m.member_id = e.member_id
WHERE e.enroll_id IS NULL;