-- Property Rental and Lease Management System  (MySQL 8.0.16+)
-- Pasham Akshitha | 25WU0102195
DROP DATABASE IF EXISTS rental_db;
CREATE DATABASE rental_db;
USE rental_db;

-- ================= TABLES (3NF) =================
CREATE TABLE owner (
  owner_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(80) NOT NULL,
  email VARCHAR(100) NOT NULL UNIQUE,                 -- unique owner email
  phone CHAR(10) NOT NULL,
  password_hash CHAR(64) NOT NULL,
  CONSTRAINT ck_owner_phone CHECK (phone REGEXP '^[0-9]{10}$')
);

CREATE TABLE tenant (
  tenant_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(80) NOT NULL,
  email VARCHAR(100) NOT NULL UNIQUE,                 -- unique tenant email
  phone CHAR(10) NOT NULL,
  password_hash CHAR(64) NOT NULL,
  CONSTRAINT ck_tenant_phone CHECK (phone REGEXP '^[0-9]{10}$')
);

CREATE TABLE property (
  property_id INT AUTO_INCREMENT PRIMARY KEY,
  owner_id INT NOT NULL,
  name VARCHAR(100) NOT NULL,
  city VARCHAR(50) NOT NULL,
  address VARCHAR(150) NOT NULL,
  FOREIGN KEY (owner_id) REFERENCES owner(owner_id)
);

CREATE TABLE unit (
  unit_id INT AUTO_INCREMENT PRIMARY KEY,
  property_id INT NOT NULL,
  unit_no VARCHAR(10) NOT NULL,
  bhk ENUM('1BHK','2BHK','3BHK') NOT NULL DEFAULT '1BHK',
  rent DECIMAL(10,2) NOT NULL,
  deposit_amt DECIMAL(10,2) NOT NULL,
  status ENUM('Available','Occupied') NOT NULL DEFAULT 'Available',
  UNIQUE (property_id, unit_no),
  CONSTRAINT ck_unit_rent CHECK (rent >= 0),          -- non-negative rent
  CONSTRAINT ck_unit_dep  CHECK (deposit_amt >= 0),   -- non-negative deposit
  FOREIGN KEY (property_id) REFERENCES property(property_id)
);

CREATE TABLE lease (
  lease_id INT AUTO_INCREMENT PRIMARY KEY,
  unit_id INT NOT NULL,
  tenant_id INT NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  monthly_rent DECIMAL(10,2) NOT NULL,
  status ENUM('Active','Ended') NOT NULL DEFAULT 'Active',
  CONSTRAINT ck_lease_dates CHECK (end_date > start_date),   -- valid lease dates
  CONSTRAINT ck_lease_rent  CHECK (monthly_rent >= 0),
  FOREIGN KEY (unit_id) REFERENCES unit(unit_id),
  FOREIGN KEY (tenant_id) REFERENCES tenant(tenant_id)
);

CREATE TABLE deposit (
  deposit_id INT AUTO_INCREMENT PRIMARY KEY,
  lease_id INT NOT NULL UNIQUE,
  amount DECIMAL(10,2) NOT NULL,
  status ENUM('Held','Refunded') NOT NULL DEFAULT 'Held',
  refund_date DATE NULL,
  CONSTRAINT ck_dep_amt CHECK (amount >= 0),
  FOREIGN KEY (lease_id) REFERENCES lease(lease_id)
);

CREATE TABLE rent_payment (
  payment_id INT AUTO_INCREMENT PRIMARY KEY,
  lease_id INT NOT NULL,
  due_date DATE NOT NULL,
  amount_due DECIMAL(10,2) NOT NULL,
  amount_paid DECIMAL(10,2) NOT NULL DEFAULT 0,
  paid_date DATE NULL,
  status ENUM('Pending','Partial','Paid') NOT NULL DEFAULT 'Pending',
  UNIQUE (lease_id, due_date),
  CONSTRAINT ck_pay_due  CHECK (amount_due > 0),
  CONSTRAINT ck_pay_paid CHECK (amount_paid >= 0 AND amount_paid <= amount_due),  -- valid payment
  FOREIGN KEY (lease_id) REFERENCES lease(lease_id)
);

CREATE TABLE inspection (
  inspection_id INT AUTO_INCREMENT PRIMARY KEY,
  unit_id INT NOT NULL,
  inspection_date DATE NOT NULL,
  condition_status ENUM('Good','Fair','Poor') NOT NULL DEFAULT 'Good',
  notes VARCHAR(200),
  FOREIGN KEY (unit_id) REFERENCES unit(unit_id)
);

CREATE TABLE maintenance_request (
  request_id INT AUTO_INCREMENT PRIMARY KEY,
  unit_id INT NOT NULL,
  tenant_id INT NOT NULL,
  issue VARCHAR(200) NOT NULL,
  priority ENUM('Low','Medium','High') NOT NULL DEFAULT 'Medium',
  status ENUM('Open','In Progress','Resolved') NOT NULL DEFAULT 'Open',
  raised_on DATE NOT NULL DEFAULT (CURRENT_DATE),
  FOREIGN KEY (unit_id) REFERENCES unit(unit_id),
  FOREIGN KEY (tenant_id) REFERENCES tenant(tenant_id)
);

CREATE TABLE renewal (
  renewal_id INT AUTO_INCREMENT PRIMARY KEY,
  lease_id INT NOT NULL,
  months INT NOT NULL,
  status ENUM('Pending','Approved','Rejected') NOT NULL DEFAULT 'Pending',
  requested_on DATE NOT NULL DEFAULT (CURRENT_DATE),
  CONSTRAINT ck_ren_months CHECK (months BETWEEN 1 AND 36),
  FOREIGN KEY (lease_id) REFERENCES lease(lease_id)
);

-- ================= INDEXES (frequently searched columns) =================
CREATE INDEX idx_property_city   ON property(city);
CREATE INDEX idx_unit_status     ON unit(status);
CREATE INDEX idx_lease_unit_stat ON lease(unit_id, status);
CREATE INDEX idx_lease_tenant    ON lease(tenant_id);
CREATE INDEX idx_pay_status_due  ON rent_payment(status, due_date);
CREATE INDEX idx_maint_status    ON maintenance_request(status);

-- ================= TRIGGERS (business rules) =================
DELIMITER $$

-- Rule: only available units can be leased + no overlapping active lease
CREATE TRIGGER trg_lease_bi BEFORE INSERT ON lease FOR EACH ROW
BEGIN
  DECLARE st VARCHAR(10);
  SELECT status INTO st FROM unit WHERE unit_id = NEW.unit_id;
  IF st IS NULL OR st <> 'Available' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unit is not available for lease';
  END IF;
  IF EXISTS (SELECT 1 FROM lease WHERE unit_id = NEW.unit_id AND status = 'Active'
             AND NEW.start_date <= end_date AND NEW.end_date >= start_date) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Overlapping active lease for this unit';
  END IF;
END$$

-- New lease: mark unit occupied and record the security deposit
CREATE TRIGGER trg_lease_ai AFTER INSERT ON lease FOR EACH ROW
BEGIN
  UPDATE unit SET status = 'Occupied' WHERE unit_id = NEW.unit_id;
  INSERT INTO deposit(lease_id, amount) SELECT NEW.lease_id, deposit_amt FROM unit WHERE unit_id = NEW.unit_id;
END$$

-- Lease ended: free the unit and refund the deposit
CREATE TRIGGER trg_lease_au AFTER UPDATE ON lease FOR EACH ROW
BEGIN
  IF OLD.status = 'Active' AND NEW.status = 'Ended' THEN
    UPDATE unit SET status = 'Available' WHERE unit_id = NEW.unit_id;
    UPDATE deposit SET status = 'Refunded', refund_date = CURDATE() WHERE lease_id = NEW.lease_id;
  END IF;
END$$

-- Auto-compute payment status
CREATE TRIGGER trg_pay_bi BEFORE INSERT ON rent_payment FOR EACH ROW
BEGIN
  SET NEW.status = IF(NEW.amount_paid >= NEW.amount_due, 'Paid', IF(NEW.amount_paid > 0, 'Partial', 'Pending'));
  IF NEW.amount_paid > 0 AND NEW.paid_date IS NULL THEN SET NEW.paid_date = CURDATE(); END IF;
END$$

CREATE TRIGGER trg_pay_bu BEFORE UPDATE ON rent_payment FOR EACH ROW
BEGIN
  SET NEW.status = IF(NEW.amount_paid >= NEW.amount_due, 'Paid', IF(NEW.amount_paid > 0, 'Partial', 'Pending'));
  IF NEW.amount_paid > OLD.amount_paid THEN SET NEW.paid_date = CURDATE(); END IF;
END$$
DELIMITER ;

-- ================= SAMPLE DATA =================
INSERT INTO owner(name,email,phone,password_hash) VALUES
('Ramesh Naidu','ramesh@owner.com','9876500001',SHA2('owner123',256)),
('Lakshmi Devi','lakshmi@owner.com','9876500002',SHA2('owner123',256));

INSERT INTO tenant(name,email,phone,password_hash) VALUES
('Anil Verma','anil@tenant.com','9876500003',SHA2('tenant123',256)),
('Divya Reddy','divya@tenant.com','9876500004',SHA2('tenant123',256)),
('Suresh Babu','suresh@tenant.com','9876500005',SHA2('tenant123',256));

INSERT INTO property(owner_id,name,city,address) VALUES
(1,'Green Villa Apartments','Hyderabad','Madhapur'),
(1,'Sunrise Residency','Warangal','Hanamkonda'),
(2,'Lake View Towers','Hyderabad','Gachibowli');

INSERT INTO unit(property_id,unit_no,bhk,rent,deposit_amt) VALUES
(1,'A-101','2BHK',15000,30000),(1,'A-102','1BHK',9000,18000),
(2,'B-1','2BHK',12000,24000),(2,'B-2','3BHK',18000,36000),
(3,'T-501','3BHK',25000,50000),(3,'T-502','2BHK',20000,40000);

-- historical lease (ended), then two active leases (triggers set unit status + deposits)
INSERT INTO lease(unit_id,tenant_id,start_date,end_date,monthly_rent) VALUES (2,3,'2025-01-01','2025-12-31',9000);
UPDATE lease SET status='Ended' WHERE lease_id = 1;
INSERT INTO lease(unit_id,tenant_id,start_date,end_date,monthly_rent) VALUES
(1,1,'2026-01-01','2026-12-31',15000),
(3,2,'2026-03-01','2026-10-31',12000);

INSERT INTO rent_payment(lease_id,due_date,amount_due,amount_paid) VALUES
(2,'2026-08-01',15000,15000),(2,'2026-09-01',15000,15000),(2,'2026-10-01',15000,0),(2,'2026-11-01',15000,0),
(3,'2026-08-01',12000,12000),(3,'2026-09-01',12000,12000),(3,'2026-10-01',12000,5000);

INSERT INTO inspection(unit_id,inspection_date,condition_status,notes) VALUES
(1,'2026-06-15','Good','Routine check, no damage'),(3,'2026-07-10','Fair','Minor wall dampness');

INSERT INTO maintenance_request(unit_id,tenant_id,issue,priority,status,raised_on) VALUES
(1,1,'Water leakage in bathroom','High','Open','2026-10-03'),
(3,2,'AC not cooling','Medium','In Progress','2026-09-28');

INSERT INTO renewal(lease_id,months) VALUES (3,12);
