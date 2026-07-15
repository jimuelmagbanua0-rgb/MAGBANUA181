USE walang_brownout;

-- =============================================
-- TRIGGER 1: Low Stock Alert
-- Auto-creates alert when stock is low
-- =============================================
DELIMITER $$

CREATE TRIGGER trg_check_low_stock_after_update
AFTER UPDATE ON inventory
FOR EACH ROW
BEGIN
    DECLARE reorder_point_val INT;
    DECLARE product_name_val VARCHAR(200);
    
    SELECT reorder_point INTO reorder_point_val 
    FROM reorder_points 
    WHERE product_id = NEW.product_id;
    
    SELECT product_name INTO product_name_val 
    FROM products 
    WHERE product_id = NEW.product_id;
    
    IF NEW.available_quantity < reorder_point_val AND NEW.available_quantity > 0 THEN
        INSERT INTO alerts (product_id, alert_type, severity, message, recommended_action)
        VALUES (
            NEW.product_id,
            'LOW_STOCK',
            'CRITICAL',
            CONCAT('LOW STOCK ALERT: ', product_name_val, 
                   ' has only ', NEW.available_quantity, ' units available.'),
            CONCAT('Immediately reorder ', product_name_val, 
                   '. Recommended order: ', (reorder_point_val * 2) - NEW.available_quantity, ' units.')
        );
    END IF;
    
    IF NEW.available_quantity = 0 THEN
        INSERT INTO alerts (product_id, alert_type, severity, message, recommended_action)
        VALUES (
            NEW.product_id,
            'LOW_STOCK',
            'CRITICAL',
            CONCAT('OUT OF STOCK: ', product_name_val, ' is completely depleted!'),
            CONCAT('URGENT: Place emergency order for ', product_name_val)
        );
    END IF;
END$$

DELIMITER ;

-- =============================================
-- TRIGGER 2: Expiry Alert
-- Auto-creates alert when items near expiry
-- =============================================
DELIMITER $$

CREATE TRIGGER trg_check_expiry_after_insert
AFTER INSERT ON inventory
FOR EACH ROW
BEGIN
    DECLARE days_until_expiry INT;
    DECLARE product_name_val VARCHAR(200);
    
    IF NEW.expiry_date IS NOT NULL THEN
        SET days_until_expiry = DATEDIFF(NEW.expiry_date, CURDATE());
        
        SELECT product_name INTO product_name_val 
        FROM products 
        WHERE product_id = NEW.product_id;
        
        -- CRITICAL: Expired
        IF days_until_expiry < 0 THEN
            INSERT INTO alerts (product_id, alert_type, severity, message, recommended_action)
            VALUES (
                NEW.product_id,
                'EXPIRY',
                'CRITICAL',
                CONCAT('EXPIRED: ', product_name_val, ' (Batch: ', NEW.batch_number, 
                       ') expired on ', NEW.expiry_date),
                'Remove this batch immediately. Dispose properly.'
            );
        
        -- WARNING: Nearing expiry (within 60 days)
        ELSEIF days_until_expiry <= 60 AND days_until_expiry > 0 THEN
            INSERT INTO alerts (product_id, alert_type, severity, message, recommended_action)
            VALUES (
                NEW.product_id,
                'EXPIRY',
                'WARNING',
                CONCAT('NEARING EXPIRY: ', product_name_val, ' (Batch: ', NEW.batch_number, 
                       ') expires in ', days_until_expiry, ' days'),
                'Prioritize this batch for sale. Consider discount promotion.'
            );
        END IF;
    END IF;
END$$

DELIMITER ;

-- =============================================
-- TRIGGER 3: FIFO Compliance Alert
-- Warns if newer stock is picked first
-- =============================================
DELIMITER $$

CREATE TRIGGER trg_check_fifo_compliance
BEFORE UPDATE ON inventory
FOR EACH ROW
BEGIN
    DECLARE older_batch_available INT;
    DECLARE product_name_val VARCHAR(200);
    
    IF NEW.quantity < OLD.quantity AND NEW.expiry_date IS NOT NULL THEN
        SELECT COUNT(*) INTO older_batch_available
        FROM inventory 
        WHERE product_id = NEW.product_id 
          AND manufacturing_date < OLD.manufacturing_date 
          AND available_quantity > 0;
        
        IF older_batch_available > 0 THEN
            SELECT product_name INTO product_name_val 
            FROM products 
            WHERE product_id = NEW.product_id;
            
            INSERT INTO alerts (product_id, alert_type, severity, message, recommended_action)
            VALUES (
                NEW.product_id,
                'FIFO_WARNING',
                'WARNING',
                CONCAT('FIFO VIOLATION: Newer batch of ', product_name_val, 
                       ' (Batch: ', NEW.batch_number, ') being picked before older stock'),
                'Retrieve from older batches first. Check warehouse location.'
            );
        END IF;
    END IF;
END$$

DELIMITER ;

-- =============================================
-- TRIGGER 4: Discrepancy Alert
-- Compares system vs physical count
-- =============================================
DELIMITER $$

CREATE TRIGGER trg_check_discrepancy_after_update
AFTER UPDATE ON inventory
FOR EACH ROW
BEGIN
    DECLARE product_name_val VARCHAR(200);
    
    IF NEW.last_physical_count IS NOT NULL AND 
       (OLD.last_physical_count IS NULL OR NEW.last_physical_count > OLD.last_physical_count) THEN
        IF NEW.quantity != OLD.quantity AND ABS(NEW.quantity - OLD.quantity) > 5 THEN
            SELECT product_name INTO product_name_val 
            FROM products 
            WHERE product_id = NEW.product_id;
            
            INSERT INTO alerts (product_id, alert_type, severity, message, recommended_action)
            VALUES (
                NEW.product_id,
                'DISCREPANCY',
                'CRITICAL',
                CONCAT('INVENTORY DISCREPANCY: ', product_name_val, 
                       ' System: ', OLD.quantity, ', Physical: ', NEW.quantity),
                'Immediate investigation required. Check for theft or misplacement.'
            );
        END IF;
    END IF;
END$$

DELIMITER ;

-- =============================================
-- TRIGGER 5: Auto Transaction Log
-- Logs every inventory change
-- =============================================
DELIMITER $$

CREATE TRIGGER trg_log_transaction_after_update
AFTER UPDATE ON inventory
FOR EACH ROW
BEGIN
    DECLARE transaction_type_val VARCHAR(20);
    DECLARE quantity_change INT;
    
    SET quantity_change = NEW.quantity - OLD.quantity;
    
    IF quantity_change > 0 THEN
        SET transaction_type_val = 'RECEIVED';
    ELSEIF quantity_change < 0 THEN
        SET transaction_type_val = 'SOLD';
    ELSE
        SET transaction_type_val = 'ADJUSTED';
    END IF;
    
    IF quantity_change != 0 OR NEW.status != OLD.status THEN
        INSERT INTO transactions (product_id, inventory_id, transaction_type, quantity, 
                                  reference_number, notes, performed_by)
        VALUES (
            NEW.product_id,
            NEW.inventory_id,
            transaction_type_val,
            ABS(quantity_change),
            CONCAT('AUTO-', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s')),
            CONCAT('Auto-log for batch: ', NEW.batch_number),
            'SYSTEM'
        );
    END IF;
END$$

DELIMITER ;
