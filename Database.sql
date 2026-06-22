Create table Employee (
    employee_id int primary key,
    job_id varchar(1) check(job_id in('S','M','C')),
    phone_number varchar(20),
    salary decimal(12,2),
    tariff decimal(12,2),
    first_name varchar(50),
    last_name varchar(50),
    salary_af_tariff decimal(12,2) generated always as (salary - tariff) stored
);

Create table Member (
    member_id int primary key,
    first_name varchar(50),
    last_name varchar(50),
    email varchar(100),
    phone_number varchar(20)
);

Create table Member_body_perweek (
    member_id int,
    week int,
    date date,
    body_fat decimal(5,2),
    muscle_mass decimal(5,2),
    foreign key(member_id) references Member(member_id),
    primary key(member_id, week)
);

CREATE TABLE Service (
    service_id SERIAL PRIMARY KEY,
    service_name VARCHAR(255) NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    service_type VARCHAR(50) NOT NULL -- Lưu giá trị: 'PACKAGE' hoặc 'CLASS'
);
--Bảng phòng
create table Room (
    room_id int primary key,
    manager_id int,
    foreign key(manager_id) references Employee(employee_id)
);

-- Bảng Gói tập
CREATE TABLE Package (
    service_id INT PRIMARY KEY, -- Vừa là PK, vừa là FK
    duration_in_months INT NOT NULL,
    information varchar(50),
    room_id int,
    FOREIGN KEY (room_id) REFERENCES  room(room_id),
    FOREIGN KEY (service_id) REFERENCES service(service_id) ON DELETE CASCADE
);

CREATE TABLE Class (
    class_id INT PRIMARY KEY, -- Vừa là PK, vừa là FK
    maximum_students INT NOT NULL,
    information varchar(50),
    FOREIGN KEY (room_id) REFERENCES  room(room_id),
    FOREIGN KEY (class_id) REFERENCES service(service_id) ON DELETE CASCADE
);


CREATE TABLE Enroll (
    enroll_id SERIAL PRIMARY KEY,
    member_id INT REFERENCES member(member_id),
    service_id INT REFERENCES service(service_id), -- Trỏ thẳng về Service
    start_date DATE,
    end_date DATE,
    status varchar(20) check(status in('active','inactive','frozen'))
);

Create table Payment (
    payment_id serial primary key,
    member_id int,
    staff_id int,
    date date,
    time time,
    service_id INT REFERENCES service(service_id), -- Trỏ thẳng về Service
    total_price decimal(12,2),
    foreign key(member_id) references Member(member_id),
    foreign key(staff_id) references Staff(staff_id)
);

CREATE TABLE Payment_detail (
    payment_detail_id SERIAL PRIMARY KEY,
    payment_id INT REFERENCES payment(payment_id),
    service_id INT REFERENCES service(service_id), -- Trỏ thẳng về Service
    unit_price DECIMAL(10, 2)
);


create table Staff_Room ( --quản lí nhân viên nào dọn phòng nào
    staff_id int,
    room_id int,
    foreign key(staff_id) references Employee(employee_id),
    foreign key(room_id) references Room(room_id),
    primary key(staff_id, room_id)
);

Create table Coach_Checkin (
    coach_id int,
    class_id int,
    date date,
    primary key (coach_id,shift_id),
    present varchar(20) check(present in('yes','execute_absent','absent')),     -- Có mặt, vắng mặt không phép, vắng mặt có phép
    foreign key(coach_id) references Coach(coach_id),
    foreign key(shift_id) references Shift(shift_id)
);

create table Shift (
    shift_id int primary key identity(1,1),
    shift_number int check(shift_number in(1,2,3,4)),
    time_begin time,
    time_end time = time_begin + 3
);

Create table Staff_Checkin (
    staff_id int,
    shift_id int,
    date date,
    present varchar(20) check(present in('yes','execute_absent','absent')),     -- Có mặt, vắng mặt không phép, vắng mặt có phép
    foreign key(staff_id) references Staff(staff_id),
    foreign key(shift_id) references Shift(shift_id)
);


create table Device (
    device_id int primary key,
    room_id int,
    foreign key(room_id) references Room(room_id),
    purchase int,
    status varchar(20) check(status in('Available','Broken','Too_old')),
    next_maintenance date,
    date_bought date
);

create table Shift (
    shift_id int primary key identity(1,1),
    shift_number int check(shift_number in(1,2,3)),
    time_begin time,
    time_end time = time_begin + 2
);

Create table Room_Device (
    room_id int,
    device_id int,
    foreign key(room_id) references Room(room_id),
    foreign key(device_id) references Device(device_id),
    primary key(room_id, device_id)
);

Create table Fee (
    fee_id varchar(50) primary key,
    water_cost decimal(12,2),
    power_cost decimal(12,2),
    other_cost decimal(12,2),
    total_cost generated always as (water_cost + power_cost + other_cost) stored,
    pay_date date
);

Create table Repair (
    device_id int,
    repair_date date,
    payment decimal(12,2),
    repair_unit varchar(50),
    status varchar(20) check(status in('pending','completed')),
    foreign key(device_id) references Device(device_id)
);