USE walang_brownout;

-- =============================================
-- PROCEDURE 1: Daily Health Check
-- Run this daily to check all inventory issues
-- =============================================
DELIMITER $$

CREATE PROCEDURE sp_daily_health_check()
BEGIN
    -- 1. CHECK LOW STOCK
    INSERT INTO alerts (product_id, alert_type, severity, message, recommended_action)
    SELECT 
        p.product_id,
        'LOW_STOCK',
        'CRITICAL',
        CONCAT('LOW STOCK: ', p.product_name, ' has only ', 
               COALESCE(SUM(i.available_quantity), 0), ' units available.'),
        CONCAT('Order ', (SELECT reorder_point FROM reorder_points WHERE product_id = p.product_id) - 
               COALESCE(SUM(i.available_quantity), 0), ' units immediately.')
    FROM products p
    LEFT JOIN inventory i ON p.product_id = i.product_id AND i.status = 'AVAILABLE'
    WHERE COALESCE(SUM(i.available_quantity), 0) < (
        SELECT reorder_point FROM reorder_points WHERE product_id = p.product_id
    )
    GROUP BY p.product_id;
    
    -- 2. CHECK EXPIRY (within 60 days)
    INSERT INTO alerts (product_id, alert_type, severity, message, recommended_action)
    SELECT 
        product_id,
        'EXPIRY',
        'WARNING',
        CONCAT('NEARING EXPIRY: ', p.product_name, ' (Batch: ', i.batch_number, 
               ') expires in ', DATEDIFF(i.expiry_date, CURDATE()), ' days.'),
        'Priority sale needed. Consider markdown.'
    FROM inventory i
    JOIN products p ON i.product_id = p.product_id
    WHERE i.expiry_date IS NOT NULL
      AND i.status = 'AVAILABLE'
      AND DATEDIFF(i.expiry_date, CURDATE()) BETWEEN 1 AND 60
      AND i.quantity > 0;
    
    -- 3. CHECK EXPIRED ITEMS
    INSERT INTO alerts (product_id, alert_type, severity, message, recommended_action)
    SELECT 
        product_id,
        'EXPIRY',
        'CRITICAL',
        CONCAT('EXPIRED: ', p.product_name, ' (Batch: ', i.batch_number, 
               ') expired on ', i.expiry_date, '.'),
        'Remove from inventory immediately. Dispose properly.'
    FROM inventory i
    JOIN products p ON i.product_id = p.product_id
    WHERE i.expiry_date IS NOT NULL
      AND i.expiry_date < CURDATE()
      AND i.status = 'AVAILABLE'
      AND i.quantity > 0;
    
    -- 4. CHECK OVERSTOCK (Summer items in winter)
    INSERT INTO alerts (product_id, alert_type, severity, message, recommended_action)
    SELECT 
        p.product_id,
        'OVERSTOCK',
        'WARNING',
        CONCAT('OVERSTOCK: ', p.product_name, ' has ', 
               COALESCE(SUM(i.quantity), 0), ' units in storage.'),
        'Review storage costs. Consider promotions or reduce future orders.'
    FROM products p
    LEFT JOIN inventory i ON p.product_id = i.product_id AND i.status = 'AVAILABLE'
    WHERE p.seasonality = 'SUMMER'
      AND MONTH(CURDATE()) IN (12, 1, 2)
    GROUP BY p.product_id
    HAVING COALESCE(SUM(i.quantity), 0) > (
        SELECT max_stock FROM reorder_points WHERE product_id = p.product_id
    );
END$$

DELIMITER ;

-- =============================================
-- PROCEDURE 2: Reconcile Inventory
-- Compare system count vs physical count
-- =============================================
DELIMITER $$

CREATE PROCEDURE sp_reconcile_inventory(
    IN p_product_id INT,
    IN p_physical_count INT
)
BEGIN
    DECLARE system_count INT;
    DECLARE product_name_val VARCHAR(200);
    
    SELECT COALESCE(SUM(available_quantity), 0) INTO system_count
    FROM inventory
    WHERE product_id = p_product_id AND status = 'AVAILABLE';
    
    SELECT product_name INTO product_name_val
    FROM products
    WHERE product_id = p_product_id;
    
    IF ABS(system_count - p_physical_count) > 5 THEN
        INSERT INTO alerts (product_id, alert_type, severity, message, recommended_action)
        VALUES (
            p_product_id,
            'DISCREPANCY',
            'CRITICAL',
            CONCAT('INVENTORY DISCREPANCY: ', product_name_val,
                   ' System: ', system_count, ', Physical: ', p_physical_count),
            'Immediate investigation required. Check for theft, damage, or misplacement.'
        );
        
        SELECT 
            p_product_id AS product_id,
            product_name_val AS product_name,
            system_count AS system_count,
            p_physical_count AS physical_count,
            (system_count - p_physical_count) AS difference,
            'DISCREPANCY_DETECTED' AS status;
    ELSE
        SELECT 
            p_product_id AS product_id,
            product_name_val AS product_name,
            system_count AS system_count,
            p_physical_count AS physical_count,
            0 AS difference,
            'RECONCILED' AS status;
    END IF;
END$$

DELIMITER ;

-- =============================================
-- PROCEDURE 3: Get Active Alerts
-- View all unresolved alerts
-- =============================================
DELIMITER $$

CREATE PROCEDURE sp_get_active_alerts()
BEGIN
    SELECT 
        a.alert_id,
        a.product_id,
        p.product_name,
        p.sku,
        a.alert_type,
        a.severity,
        a.message,
        a.recommended_action,
        a.created_at,
        DATEDIFF(NOW(), a.created_at) AS days_old
    FROM alerts a
    JOIN products p ON a.product_id = p.product_id
    WHERE a.is_resolved = FALSE
    ORDER BY 
        FIELD(a.severity, 'CRITICAL', 'WARNING', 'INFO'),
        a.created_at DESC;
END$$

DELIMITER ;

-- =============================================
-- PROCEDURE 4: Resolve Alert
-- Mark alert as resolved
-- =============================================
DELIMITER $$

CREATE PROCEDURE sp_resolve_alert(
    IN p_alert_id INT,
    IN p_resolved_by VARCHAR(100),
    IN p_notes TEXT
)
BEGIN
    UPDATE alerts
    SET 
        is_resolved = TRUE,
        resolved_at = NOW(),
        resolved_by = p_resolved_by
    WHERE alert_id = p_alert_id;
    
    SELECT 'Alert resolved successfully' AS result;
END$$

DELIMITER ;

-- =============================================
-- PROCEDURE 5: Update Seasonal Reorder Points
-- Run this monthly
-- =============================================
DELIMITER $$

CREATE PROCEDURE sp_update_seasonal_reorder()
BEGIN
    DECLARE current_month INT;
    SET current_month = MONTH(CURDATE());
    
    IF current_month BETWEEN 6 AND 8 THEN
        UPDATE reorder_points rp
        JOIN products p ON rp.product_id = p.product_id
        SET 
            rp.reorder_point = rp.reorder_point * 1.5,
            rp.seasonal_multiplier = 1.5,
            rp.last_review_date = CURDATE()
        WHERE p.seasonality = 'SUMMER';
        
    ELSEIF current_month BETWEEN 9 AND 11 THEN
        UPDATE reorder_points rp
        JOIN products p ON rp.product_id = p.product_id
        SET 
            rp.reorder_point = rp.reorder_point * 1.2,
            rp.seasonal_multiplier = 1.2,
            rp.last_review_date = CURDATE()
        WHERE p.seasonality = 'SUMMER';
        
    ELSE
        UPDATE reorder_points rp
        JOIN products p ON rp.product_id = p.product_id
        SET 
            rp.reorder_point = rp.reorder_point * 0.8,
            rp.seasonal_multiplier = 0.8,
            rp.last_review_date = CURDATE()
        WHERE p.seasonality = 'SUMMER';
    END IF;
END$$

DELIMITER ;
