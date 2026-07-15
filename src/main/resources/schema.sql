-- Drop existing database if it exists
DROP DATABASE IF EXISTS walang_brownout;

-- Create fresh database
CREATE DATABASE walang_brownout;
USE walang_brownout;

-- =============================================
-- TABLE 1: PRODUCTS MASTER
-- =============================================
CREATE TABLE products (
    product_id INT PRIMARY KEY AUTO_INCREMENT,
    sku VARCHAR(50) UNIQUE NOT NULL COMMENT 'Stock Keeping Unit',
    product_name VARCHAR(200) NOT NULL,
    category ENUM('AC_UNIT', 'AIR_PURIFIER', 'FILTER', 'THERMOSTAT') NOT NULL,
    sub_category VARCHAR(100),
    unit_price DECIMAL(10,2) NOT NULL,
    weight_kg DECIMAL(8,2),
    shelf_life_months INT COMMENT 'NULL for non-perishable',
    seasonality ENUM('SUMMER', 'WINTER', 'YEAR_ROUND') DEFAULT 'YEAR_ROUND',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_category (category),
    INDEX idx_seasonality (seasonality)
);

-- =============================================
-- TABLE 2: INVENTORY (Real-time tracking)
-- =============================================
CREATE TABLE inventory (
    inventory_id INT PRIMARY KEY AUTO_INCREMENT,
    product_id INT NOT NULL,
    batch_number VARCHAR(50) NOT NULL,
    manufacturing_date DATE NOT NULL,
    expiry_date DATE,
    quantity INT NOT NULL DEFAULT 0,
    reserved_quantity INT DEFAULT 0,
    available_quantity INT GENERATED ALWAYS AS (quantity - reserved_quantity) STORED,
    warehouse_location VARCHAR(50) NOT NULL,
    received_date DATE NOT NULL,
    last_physical_count DATE,
    status ENUM('AVAILABLE', 'RESERVED', 'EXPIRED', 'DAMAGED', 'SOLD') DEFAULT 'AVAILABLE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE,
    INDEX idx_product_batch (product_id, batch_number),
    INDEX idx_expiry (expiry_date),
    INDEX idx_available (available_quantity)
);

-- =============================================
-- TABLE 3: TRANSACTIONS (Audit Trail)
-- =============================================
CREATE TABLE transactions (
    transaction_id INT PRIMARY KEY AUTO_INCREMENT,
    product_id INT NOT NULL,
    inventory_id INT NOT NULL,
    transaction_type ENUM('RECEIVED', 'SOLD', 'RESERVED', 'RETURNED', 
                          'ADJUSTED', 'EXPIRED', 'DAMAGED') NOT NULL,
    quantity INT NOT NULL,
    reference_number VARCHAR(100),
    notes TEXT,
    performed_by VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(product_id),
    FOREIGN KEY (inventory_id) REFERENCES inventory(inventory_id),
    INDEX idx_product (product_id),
    INDEX idx_created (created_at)
);

-- =============================================
-- TABLE 4: REORDER POINTS
-- =============================================
CREATE TABLE reorder_points (
    reorder_id INT PRIMARY KEY AUTO_INCREMENT,
    product_id INT NOT NULL UNIQUE,
    min_stock INT NOT NULL COMMENT 'Safety stock',
    max_stock INT NOT NULL COMMENT 'Maximum capacity',
    reorder_point INT NOT NULL COMMENT 'Trigger threshold',
    seasonal_multiplier DECIMAL(3,2) DEFAULT 1.00,
    lead_time_days INT DEFAULT 7,
    last_review_date DATE,
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE
);

-- =============================================
-- TABLE 5: ALERTS (Your main focus!)
-- =============================================
CREATE TABLE alerts (
    alert_id INT PRIMARY KEY AUTO_INCREMENT,
    product_id INT NOT NULL,
    alert_type ENUM('LOW_STOCK', 'EXPIRY', 'DISCREPANCY', 'OVERSTOCK', 'FIFO_WARNING') NOT NULL,
    severity ENUM('INFO', 'WARNING', 'CRITICAL') NOT NULL,
    message TEXT NOT NULL,
    recommended_action TEXT,
    is_resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP NULL,
    resolved_by VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE,
    INDEX idx_resolved (is_resolved),
    INDEX idx_type (alert_type)
);

-- =============================================
-- SAMPLE DATA (All 3 case study problems)
-- =============================================

-- Products
INSERT INTO products (sku, product_name, category, unit_price, shelf_life_months, seasonality) VALUES
('AC-001', 'Portable AC 1.5HP', 'AC_UNIT', 15999.00, NULL, 'SUMMER'),
('AC-002', 'Portable AC 2.0HP', 'AC_UNIT', 18999.00, NULL, 'SUMMER'),
('AP-001', 'Air Purifier HEPA', 'AIR_PURIFIER', 8999.00, NULL, 'YEAR_ROUND'),
('FL-001', 'HEPA Filter Replacement', 'FILTER', 1299.00, 9, 'YEAR_ROUND'),
('FL-002', 'Carbon Filter Replacement', 'FILTER', 899.00, 9, 'YEAR_ROUND'),
('TS-001', 'Smart Thermostat Pro', 'THERMOSTAT', 4999.00, NULL, 'YEAR_ROUND'),
('TS-002', 'Smart Thermostat Lite', 'THERMOSTAT', 2999.00, NULL, 'YEAR_ROUND');

-- Reorder Points
INSERT INTO reorder_points (product_id, min_stock, max_stock, reorder_point, seasonal_multiplier) VALUES
(1, 50, 500, 100, 1.5),  -- AC Units: 1.5x in summer
(2, 30, 300, 60, 1.5),
(3, 20, 150, 40, 1.0),
(4, 100, 1000, 200, 1.0),
(5, 80, 800, 150, 1.0),
(6, 15, 100, 30, 1.0),
(7, 20, 120, 40, 1.0);

-- Inventory (with specific problem scenarios)
INSERT INTO inventory (product_id, batch_number, manufacturing_date, expiry_date, 
                       quantity, reserved_quantity, warehouse_location, received_date) VALUES
-- SUMMER CRUNCH: Overstocked AC units in winter
(1, 'BATCH-AC-2024-01', '2024-06-01', NULL, 150, 20, 'A-01-01', '2024-06-15'),
(1, 'BATCH-AC-2024-02', '2024-08-15', NULL, 300, 10, 'B-02-03', '2024-09-01'),

-- MYSTERY SHRINKAGE: System says 45, but only 12 on floor
(6, 'BATCH-TS-2024-01', '2024-03-01', NULL, 45, 33, 'D-01-01', '2024-03-15'),

-- EXPIRY TRAP: Filters nearing expiry
(4, 'BATCH-FL-2024-01', '2024-01-15', '2024-10-15', 200, 5, 'C-03-01', '2024-02-01'),
(4, 'BATCH-FL-2024-02', '2024-05-20', '2025-02-20', 150, 0, 'C-03-02', '2024-06-01');

-- LOW STOCK: Below reorder point
(5, 'BATCH-CF-2024-01', '2024-04-01', '2025-01-01', 25, 5, 'E-02-01', '2024-04-15');
