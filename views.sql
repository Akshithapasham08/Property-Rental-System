USE rental_db;
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

