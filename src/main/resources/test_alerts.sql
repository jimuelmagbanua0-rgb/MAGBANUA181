USE walang_brownout;

-- =============================================
-- TEST 1: View Active Alerts
-- =============================================
CALL sp_get_active_alerts();

-- =============================================
-- TEST 2: Low Stock Alert
-- =============================================
-- Before: Check current stock
SELECT * FROM inventory WHERE product_id = 5;

-- Reduce stock below reorder point (reorder point is 150)
UPDATE inventory 
SET quantity = 20, reserved_quantity = 10 
WHERE product_id = 5 AND batch_number = 'BATCH-CF-2024-01';

-- Check if alert was created
SELECT * FROM alerts WHERE alert_type = 'LOW_STOCK' ORDER BY created_at DESC LIMIT 1;

-- =============================================
-- TEST 3: Expiry Alert
-- =============================================
-- Insert a batch that expires in 30 days
INSERT INTO inventory (product_id, batch_number, manufacturing_date, expiry_date, 
                       quantity, reserved_quantity, warehouse_location, received_date) 
VALUES (4, 'BATCH-FL-2024-TEST', '2024-01-15', DATE_ADD(CURDATE(), INTERVAL 30 DAY), 
        100, 0, 'C-03-TEST', CURDATE());

-- Check if expiry alert was created
SELECT * FROM alerts WHERE alert_type = 'EXPIRY' ORDER BY created_at DESC LIMIT 1;

-- =============================================
-- TEST 4: Discrepancy Alert
-- =============================================
-- Reconcile thermostats (system says 45, physical says 12)
CALL sp_reconcile_inventory(6, 12);

-- Check if discrepancy alert was created
SELECT * FROM alerts WHERE alert_type = 'DISCREPANCY' ORDER BY created_at DESC LIMIT 1;

-- =============================================
-- TEST 5: FIFO Warning
-- =============================================
-- Try to pick from newer batch
UPDATE inventory 
SET quantity = quantity - 10 
WHERE product_id = 4 AND batch_number = 'BATCH-FL-2024-02';

-- Check if FIFO warning was created
SELECT * FROM alerts WHERE alert_type = 'FIFO_WARNING' ORDER BY created_at DESC LIMIT 1;

-- =============================================
-- TEST 6: Daily Health Check
-- =============================================
CALL sp_daily_health_check();

-- View all alerts created
SELECT * FROM alerts ORDER BY created_at DESC LIMIT 10;

-- =============================================
-- TEST 7: Resolve an Alert
-- =============================================
-- Get an alert ID
SELECT alert_id FROM alerts WHERE is_resolved = FALSE LIMIT 1;

-- Replace 1 with actual alert_id
CALL sp_resolve_alert(1, 'Your Name', 'Stock replenished');

-- =============================================
-- TEST 8: Alert Summary
-- =============================================
SELECT 
    alert_type,
    severity,
    COUNT(*) AS count,
    SUM(CASE WHEN is_resolved = FALSE THEN 1 ELSE 0 END) AS unresolved
FROM alerts
GROUP BY alert_type, severity
ORDER BY severity DESC;

-- =============================================
-- TEST 9: Product Alert Summary
-- =============================================
SELECT 
    p.product_name,
    COUNT(a.alert_id) AS total_alerts,
    SUM(CASE WHEN a.is_resolved = FALSE THEN 1 ELSE 0 END) AS unresolved
FROM alerts a
JOIN products p ON a.product_id = p.product_id
GROUP BY a.product_id
ORDER BY total_alerts DESC;

-- =============================================
-- TEST 10: Clean Up Test Data
-- =============================================
-- Delete test alerts
DELETE FROM alerts WHERE alert_id > (SELECT MAX(alert_id)-20 FROM alerts);
