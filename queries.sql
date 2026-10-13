USE rental_db;

-- ================= VIEWS (the 7 required reports) =================
CREATE OR REPLACE VIEW v_available_units AS
SELECT p.owner_id, p.name AS property, p.city, u.unit_no, u.bhk, u.rent, u.deposit_amt
FROM unit u JOIN property p ON p.property_id = u.property_id
WHERE u.status = 'Available';

CREATE OR REPLACE VIEW v_active_leases AS
SELECT p.owner_id, p.name AS property, u.unit_no, t.name AS tenant, l.start_date, l.end_date, l.monthly_rent
FROM lease l JOIN unit u ON u.unit_id = l.unit_id
JOIN property p ON p.property_id = u.property_id
JOIN tenant t ON t.tenant_id = l.tenant_id
WHERE l.status = 'Active';

CREATE OR REPLACE VIEW v_pending_payments AS
SELECT p.owner_id, t.name AS tenant, p.name AS property, u.unit_no, r.due_date,
       (r.amount_due - r.amount_paid) AS balance
FROM rent_payment r JOIN lease l ON l.lease_id = r.lease_id
JOIN tenant t ON t.tenant_id = l.tenant_id
JOIN unit u ON u.unit_id = l.unit_id
JOIN property p ON p.property_id = u.property_id
WHERE r.status <> 'Paid' AND l.status = 'Active';

CREATE OR REPLACE VIEW v_tenant_lease_history AS
SELECT p.owner_id, t.name AS tenant, p.name AS property, u.unit_no, l.start_date, l.end_date, l.status
FROM lease l JOIN tenant t ON t.tenant_id = l.tenant_id
JOIN unit u ON u.unit_id = l.unit_id
JOIN property p ON p.property_id = u.property_id;

CREATE OR REPLACE VIEW v_property_occupancy AS
SELECT p.owner_id, p.name AS property, COUNT(u.unit_id) AS total_units,
       SUM(u.status = 'Occupied') AS occupied_units,
       ROUND(100 * SUM(u.status = 'Occupied') / COUNT(u.unit_id), 1) AS occupancy_pct
FROM property p LEFT JOIN unit u ON u.property_id = p.property_id
GROUP BY p.property_id, p.owner_id, p.name;

CREATE OR REPLACE VIEW v_maintenance AS
SELECT p.owner_id, p.name AS property, u.unit_no, t.name AS tenant, m.issue, m.priority, m.status
FROM maintenance_request m JOIN unit u ON u.unit_id = m.unit_id
JOIN property p ON p.property_id = u.property_id
JOIN tenant t ON t.tenant_id = m.tenant_id;

CREATE OR REPLACE VIEW v_renewals_due AS
SELECT p.owner_id, p.name AS property, u.unit_no, t.name AS tenant, l.end_date,
       DATEDIFF(l.end_date, CURDATE()) AS days_left
FROM lease l JOIN unit u ON u.unit_id = l.unit_id
JOIN property p ON p.property_id = u.property_id
JOIN tenant t ON t.tenant_id = l.tenant_id
WHERE l.status = 'Active' AND l.end_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 90 DAY);

SELECT * FROM v_available_units;
SELECT * FROM v_active_leases;
SELECT * FROM v_pending_payments;
SELECT * FROM v_tenant_lease_history ORDER BY tenant, start_date;
SELECT * FROM v_property_occupancy;
SELECT * FROM v_maintenance;
SELECT * FROM v_renewals_due;

-- ================= AGGREGATES =================
-- Rent collected per property
SELECT p.name, SUM(r.amount_paid) AS collected
FROM rent_payment r JOIN lease l ON l.lease_id=r.lease_id
JOIN unit u ON u.unit_id=l.unit_id JOIN property p ON p.property_id=u.property_id
GROUP BY p.name ORDER BY collected DESC;

-- Cities with more than one property
SELECT city, COUNT(*) AS properties FROM property GROUP BY city HAVING COUNT(*) > 1;

-- Average rent by unit type
SELECT bhk, ROUND(AVG(rent),2) AS avg_rent, MIN(rent) AS min_rent, MAX(rent) AS max_rent FROM unit GROUP BY bhk;

-- ================= SUBQUERIES =================
-- Units with rent above the overall average
SELECT unit_no, rent FROM unit WHERE rent > (SELECT AVG(rent) FROM unit);

-- Tenants who have never had a maintenance request
SELECT name FROM tenant WHERE tenant_id NOT IN (SELECT tenant_id FROM maintenance_request);

-- Tenants with an overdue unpaid rent
SELECT name FROM tenant t WHERE EXISTS (
  SELECT 1 FROM lease l JOIN rent_payment r ON r.lease_id=l.lease_id
  WHERE l.tenant_id=t.tenant_id AND r.status<>'Paid' AND r.due_date <= CURDATE());

-- Owner with the most properties
SELECT name FROM owner WHERE owner_id = (
  SELECT owner_id FROM property GROUP BY owner_id ORDER BY COUNT(*) DESC LIMIT 1);

-- ================= TRANSACTION EXAMPLE =================
START TRANSACTION;
UPDATE rent_payment SET amount_paid = amount_paid + 5000 WHERE lease_id = 3 AND due_date = '2026-10-01';
SELECT status, amount_paid FROM rent_payment WHERE lease_id = 3 AND due_date = '2026-10-01';
COMMIT;   -- use ROLLBACK; to undo

-- ================= CONSTRAINT TESTS (each must FAIL) =================
-- T1 overlapping/unavailable unit (unit 1 is occupied)
INSERT INTO lease(unit_id,tenant_id,start_date,end_date,monthly_rent) VALUES (1,2,'2026-06-01','2027-06-01',15000);
-- T2 invalid lease dates
INSERT INTO lease(unit_id,tenant_id,start_date,end_date,monthly_rent) VALUES (5,2,'2026-12-01','2026-06-01',25000);
-- T3 negative rent
INSERT INTO unit(property_id,unit_no,bhk,rent,deposit_amt) VALUES (1,'A-999','1BHK',-100,5000);
-- T4 duplicate email
INSERT INTO tenant(name,email,phone,password_hash) VALUES ('Dup','anil@tenant.com','9999999999','x');
-- T5 overpayment
UPDATE rent_payment SET amount_paid = 99999 WHERE payment_id = 3;
