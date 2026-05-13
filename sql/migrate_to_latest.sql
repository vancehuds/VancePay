-- VancePay manual migration script
-- Run this once after backing up your database.
-- This script is intended to replace runtime schema migration work.

SET NAMES utf8mb4;

-- Latest table definitions for missing tables.
CREATE TABLE IF NOT EXISTS vancepay_settings (
    setting_key VARCHAR(100) PRIMARY KEY,
    setting_value TEXT DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vancepay_stores (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    owner_citizenid VARCHAR(50) NOT NULL,
    balance DECIMAL(15,2) NOT NULL DEFAULT 0,
    settlement_mode ENUM('store_balance', 'public_account') NOT NULL DEFAULT 'store_balance',
    settlement_account_identifier VARCHAR(100) DEFAULT NULL,
    commission_rate DECIMAL(5,2) NOT NULL DEFAULT 0,
    tax_rate DECIMAL(5,2) NOT NULL DEFAULT 0,
    tax_exempt TINYINT(1) NOT NULL DEFAULT 0,
    tax_custom_rate_enabled TINYINT(1) NOT NULL DEFAULT 0,
    tax_settlement_mode ENUM('store_balance', 'public_account') NOT NULL DEFAULT 'store_balance',
    tax_settlement_account_identifier VARCHAR(100) DEFAULT NULL,
    status ENUM('active', 'archived') NOT NULL DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    archived_at TIMESTAMP NULL DEFAULT NULL,
    INDEX idx_owner_status (owner_citizenid, status)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vancepay_employees (
    id INT AUTO_INCREMENT PRIMARY KEY,
    store_id INT NOT NULL,
    citizenid VARCHAR(50) NOT NULL,
    role ENUM('owner', 'manager', 'cashier') NOT NULL DEFAULT 'cashier',
    can_refund TINYINT(1) NOT NULL DEFAULT 0,
    can_discount TINYINT(1) NOT NULL DEFAULT 0,
    employee_source ENUM('manual', 'public_account_sync') NOT NULL DEFAULT 'manual',
    employee_source_key VARCHAR(100) DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (store_id) REFERENCES vancepay_stores(id) ON DELETE CASCADE,
    UNIQUE KEY uk_store_employee (store_id, citizenid),
    INDEX idx_store_employee_source (store_id, employee_source, employee_source_key)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vancepay_terminals (
    id INT AUTO_INCREMENT PRIMARY KEY,
    store_id INT DEFAULT NULL,
    type ENUM('fixed', 'portable', 'tablet') NOT NULL,
    serial_number VARCHAR(50) NOT NULL UNIQUE,
    status ENUM('active', 'disabled', 'archived') NOT NULL DEFAULT 'active',
    model_key VARCHAR(50) DEFAULT NULL,
    coords JSON DEFAULT NULL,
    heading DECIMAL(6,2) DEFAULT NULL,
    created_by_citizenid VARCHAR(50) DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    archived_at TIMESTAMP NULL DEFAULT NULL,
    FOREIGN KEY (store_id) REFERENCES vancepay_stores(id) ON DELETE SET NULL,
    INDEX idx_store_type_status (store_id, type, status)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vancepay_terminal_binding_codes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(24) NOT NULL UNIQUE,
    store_id INT NOT NULL,
    terminal_type ENUM('portable', 'tablet') NOT NULL,
    created_by_citizenid VARCHAR(50) DEFAULT NULL,
    used_by_citizenid VARCHAR(50) DEFAULT NULL,
    used_terminal_id INT DEFAULT NULL,
    expires_at TIMESTAMP NOT NULL,
    used_at TIMESTAMP NULL DEFAULT NULL,
    revoked_at TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (store_id) REFERENCES vancepay_stores(id) ON DELETE CASCADE,
    FOREIGN KEY (used_terminal_id) REFERENCES vancepay_terminals(id) ON DELETE SET NULL,
    INDEX idx_store_type_status (store_id, terminal_type, expires_at, used_at, revoked_at)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vancepay_terminal_models (
    model_key VARCHAR(50) PRIMARY KEY,
    label VARCHAR(100) NOT NULL,
    model_name VARCHAR(100) NOT NULL,
    status ENUM('active', 'archived') NOT NULL DEFAULT 'active',
    is_system TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    archived_at TIMESTAMP NULL DEFAULT NULL
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vancepay_balance_entries (
    id INT AUTO_INCREMENT PRIMARY KEY,
    citizenid VARCHAR(50) NOT NULL,
    store_id INT DEFAULT NULL,
    entry_type ENUM('commission', 'commission_refund', 'withdrawal') NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    reference_code VARCHAR(32) DEFAULT NULL,
    related_reference_code VARCHAR(32) DEFAULT NULL,
    store_name_snapshot VARCHAR(100) DEFAULT NULL,
    description VARCHAR(255) DEFAULT NULL,
    available_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_citizen_available (citizenid, available_at, created_at),
    INDEX idx_reference (reference_code, related_reference_code),
    INDEX idx_store_time (store_id, created_at),
    FOREIGN KEY (store_id) REFERENCES vancepay_stores(id) ON DELETE SET NULL
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vancepay_loans (
    id INT AUTO_INCREMENT PRIMARY KEY,
    loan_code VARCHAR(32) NOT NULL UNIQUE,
    citizenid VARCHAR(50) NOT NULL,
    principal_amount DECIMAL(15,2) NOT NULL,
    interest_amount DECIMAL(15,2) NOT NULL,
    total_due DECIMAL(15,2) NOT NULL,
    repaid_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    interest_rate DECIMAL(5,2) NOT NULL DEFAULT 0,
    term_days INT NOT NULL DEFAULT 7,
    trust_score INT DEFAULT NULL,
    trust_band VARCHAR(32) DEFAULT NULL,
    status ENUM('active', 'paid', 'defaulted', 'cancelled') NOT NULL DEFAULT 'active',
    due_at TIMESTAMP NOT NULL,
    overdue_at TIMESTAMP NULL DEFAULT NULL,
    overdue_processed_at TIMESTAMP NULL DEFAULT NULL,
    ctifo_credit_event_id INT UNSIGNED DEFAULT NULL,
    repaid_at TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_citizen_status (citizenid, status, due_at),
    INDEX idx_due_status (status, due_at),
    INDEX idx_overdue_processing (status, due_at, overdue_processed_at),
    INDEX idx_ctifo_credit_event (ctifo_credit_event_id)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vancepay_collection_tasks (
    id INT AUTO_INCREMENT PRIMARY KEY,
    task_code VARCHAR(32) NOT NULL UNIQUE,
    loan_id INT NOT NULL,
    loan_code VARCHAR(32) NOT NULL,
    debtor_citizenid VARCHAR(50) NOT NULL,
    debtor_name_snapshot VARCHAR(100) DEFAULT NULL,
    debtor_phone_snapshot VARCHAR(50) DEFAULT NULL,
    principal_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    total_due DECIMAL(15,2) NOT NULL DEFAULT 0,
    outstanding_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    reward_rate DECIMAL(5,2) NOT NULL DEFAULT 0,
    reward_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    status ENUM('open', 'claimed', 'completed', 'cancelled') NOT NULL DEFAULT 'open',
    claimed_by_citizenid VARCHAR(50) DEFAULT NULL,
    claimed_by_name_snapshot VARCHAR(100) DEFAULT NULL,
    claimed_at TIMESTAMP NULL DEFAULT NULL,
    completed_at TIMESTAMP NULL DEFAULT NULL,
    reward_claimed_at TIMESTAMP NULL DEFAULT NULL,
    clue_snapshot JSON DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_collection_loan (loan_id),
    INDEX idx_collection_status (status, created_at),
    INDEX idx_collection_debtor (debtor_citizenid, status),
    INDEX idx_collection_claimed (claimed_by_citizenid, status, claimed_at),
    FOREIGN KEY (loan_id) REFERENCES vancepay_loans(id) ON DELETE CASCADE
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vancepay_payment_intents (
    id INT AUTO_INCREMENT PRIMARY KEY,
    intent_code VARCHAR(32) NOT NULL UNIQUE,
    terminal_id INT NOT NULL,
    store_id INT NOT NULL,
    cashier_citizenid VARCHAR(50) NOT NULL,
    target_citizenid VARCHAR(50) DEFAULT NULL,
    item_description VARCHAR(255) DEFAULT NULL,
    item_lines JSON DEFAULT NULL,
    subtotal_amount DECIMAL(15,2) NOT NULL,
    discount_rate DECIMAL(5,2) NOT NULL DEFAULT 0,
    discount_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    tip_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    fee_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    tax_rate DECIMAL(5,2) NOT NULL DEFAULT 0,
    tax_exempt TINYINT(1) NOT NULL DEFAULT 0,
    tax_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    commission_rate DECIMAL(5,2) NOT NULL DEFAULT 0,
    commission_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    tax_settlement_mode ENUM('store_balance', 'public_account') NOT NULL DEFAULT 'store_balance',
    tax_settlement_account_identifier VARCHAR(100) DEFAULT NULL,
    final_amount DECIMAL(15,2) NOT NULL,
    method ENUM('card', 'phone') NOT NULL,
    status ENUM(
        'pending',
        'awaiting_customer',
        'awaiting_swipe',
        'completed',
        'cancelled',
        'expired',
        'failed'
    ) NOT NULL DEFAULT 'pending',
    idempotency_key VARCHAR(64) NOT NULL,
    cancelled_reason VARCHAR(255) DEFAULT NULL,
    expires_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (terminal_id) REFERENCES vancepay_terminals(id),
    FOREIGN KEY (store_id) REFERENCES vancepay_stores(id),
    UNIQUE KEY uk_terminal_idempotency (terminal_id, idempotency_key),
    INDEX idx_target_status (target_citizenid, status, expires_at),
    INDEX idx_terminal_status (terminal_id, status, id),
    INDEX idx_status_expires (status, expires_at, id),
    INDEX idx_store_status (store_id, status),
    INDEX idx_store_created (store_id, created_at)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vancepay_transactions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    tx_code VARCHAR(32) NOT NULL UNIQUE,
    type ENUM('payment', 'refund') NOT NULL,
    intent_id INT DEFAULT NULL,
    original_tx_id INT DEFAULT NULL,
    terminal_id INT DEFAULT NULL,
    store_id INT NOT NULL,
    cashier_citizenid VARCHAR(50) DEFAULT NULL,
    customer_citizenid VARCHAR(50) NOT NULL,
    processed_by_citizenid VARCHAR(50) NOT NULL,
    store_name_snapshot VARCHAR(100) NOT NULL,
    terminal_serial_snapshot VARCHAR(50) DEFAULT NULL,
    item_description VARCHAR(255) DEFAULT NULL,
    item_lines JSON DEFAULT NULL,
    subtotal_amount DECIMAL(15,2) NOT NULL,
    discount_rate DECIMAL(5,2) NOT NULL DEFAULT 0,
    discount_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    tip_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    fee_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    tax_rate DECIMAL(5,2) NOT NULL DEFAULT 0,
    tax_exempt TINYINT(1) NOT NULL DEFAULT 0,
    tax_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    commission_rate DECIMAL(5,2) NOT NULL DEFAULT 0,
    commission_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    tax_settlement_mode ENUM('store_balance', 'public_account') NOT NULL DEFAULT 'store_balance',
    tax_settlement_account_identifier VARCHAR(100) DEFAULT NULL,
    final_amount DECIMAL(15,2) NOT NULL,
    net_amount DECIMAL(15,2) NOT NULL,
    refunded_final_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    refunded_net_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    refunded_tax_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    refunded_commission_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    method ENUM('card', 'phone') NOT NULL,
    status ENUM('completed', 'partially_refunded', 'refunded') NOT NULL DEFAULT 'completed',
    refund_reason VARCHAR(255) DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (intent_id) REFERENCES vancepay_payment_intents(id) ON DELETE SET NULL,
    FOREIGN KEY (original_tx_id) REFERENCES vancepay_transactions(id) ON DELETE SET NULL,
    FOREIGN KEY (terminal_id) REFERENCES vancepay_terminals(id) ON DELETE SET NULL,
    FOREIGN KEY (store_id) REFERENCES vancepay_stores(id),
    INDEX idx_store_time (store_id, created_at),
    INDEX idx_customer_time (customer_citizenid, created_at),
    INDEX idx_original_tx (original_tx_id)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vancepay_audit_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    actor_citizenid VARCHAR(50) NOT NULL,
    store_id INT DEFAULT NULL,
    terminal_id INT DEFAULT NULL,
    action VARCHAR(50) NOT NULL,
    target_type VARCHAR(30) NOT NULL,
    target_id VARCHAR(50) DEFAULT NULL,
    detail JSON DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_store_time (store_id, created_at),
    INDEX idx_actor_time (actor_citizenid, created_at)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vancepay_police_tickets (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ticket_code VARCHAR(32) NOT NULL UNIQUE,
    officer_citizenid VARCHAR(50) NOT NULL,
    officer_name_snapshot VARCHAR(100) DEFAULT NULL,
    target_citizenid VARCHAR(50) NOT NULL,
    target_name_snapshot VARCHAR(100) DEFAULT NULL,
    amount DECIMAL(15,2) NOT NULL,
    reason VARCHAR(255) NOT NULL,
    ticket_type VARCHAR(24) NOT NULL DEFAULT 'notice',
    ticket_style VARCHAR(24) NOT NULL DEFAULT 'aged',
    ticket_agency VARCHAR(32) NOT NULL DEFAULT 'lspd',
    status ENUM('unpaid', 'paid', 'cancelled') NOT NULL DEFAULT 'unpaid',
    ctifo_credit_event_id INT UNSIGNED DEFAULT NULL,
    ctifo_credit_impact INT NOT NULL DEFAULT 0,
    paid_at TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_ticket_target_status (target_citizenid, status, created_at),
    INDEX idx_ticket_officer_time (officer_citizenid, created_at),
    INDEX idx_ticket_agency_status_time (ticket_agency, status, created_at),
    INDEX idx_ticket_status_time (status, created_at),
    INDEX idx_ticket_ctifo_event (ctifo_credit_event_id)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO vancepay_settings (
    setting_key,
    setting_value
) VALUES
    ('default_tax_rate', '0'),
    ('tax_settlement_mode', 'store_balance'),
    ('tax_settlement_account_identifier', '')
ON DUPLICATE KEY UPDATE
    setting_value = setting_value;

-- Seed built-in terminal models.
INSERT INTO vancepay_terminal_models (
    model_key,
    label,
    model_name,
    status,
    is_system
) VALUES
    ('standard', '标准 POS 机', 'prop_till_01', 'active', 1),
    ('modern', '现代 POS 机', 'prop_till_01_ld', 'active', 1),
    ('interaction_only', '无模型交互点', 'interaction_only', 'active', 1)
ON DUPLICATE KEY UPDATE
    is_system = VALUES(is_system);

-- Convert existing tables to utf8mb4 once, instead of doing it at resource startup.
SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_settings'
        AND LOCATE('utf8mb4_', COALESCE(table_collation, '')) <> 1
);
SET @sql = IF(@needs > 0,
    'ALTER TABLE vancepay_settings CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_stores'
        AND LOCATE('utf8mb4_', COALESCE(table_collation, '')) <> 1
);
SET @sql = IF(@needs > 0,
    'ALTER TABLE vancepay_stores CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_employees'
        AND LOCATE('utf8mb4_', COALESCE(table_collation, '')) <> 1
);
SET @sql = IF(@needs > 0,
    'ALTER TABLE vancepay_employees CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_terminals'
        AND LOCATE('utf8mb4_', COALESCE(table_collation, '')) <> 1
);
SET @sql = IF(@needs > 0,
    'ALTER TABLE vancepay_terminals CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_terminal_models'
        AND LOCATE('utf8mb4_', COALESCE(table_collation, '')) <> 1
);
SET @sql = IF(@needs > 0,
    'ALTER TABLE vancepay_terminal_models CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_balance_entries'
        AND LOCATE('utf8mb4_', COALESCE(table_collation, '')) <> 1
);
SET @sql = IF(@needs > 0,
    'ALTER TABLE vancepay_balance_entries CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_loans'
        AND LOCATE('utf8mb4_', COALESCE(table_collation, '')) <> 1
);
SET @sql = IF(@needs > 0,
    'ALTER TABLE vancepay_loans CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_collection_tasks'
        AND LOCATE('utf8mb4_', COALESCE(table_collation, '')) <> 1
);
SET @sql = IF(@needs > 0,
    'ALTER TABLE vancepay_collection_tasks CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND LOCATE('utf8mb4_', COALESCE(table_collation, '')) <> 1
);
SET @sql = IF(@needs > 0,
    'ALTER TABLE vancepay_payment_intents CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND LOCATE('utf8mb4_', COALESCE(table_collation, '')) <> 1
);
SET @sql = IF(@needs > 0,
    'ALTER TABLE vancepay_transactions CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_audit_logs'
        AND LOCATE('utf8mb4_', COALESCE(table_collation, '')) <> 1
);
SET @sql = IF(@needs > 0,
    'ALTER TABLE vancepay_audit_logs CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_police_tickets'
        AND LOCATE('utf8mb4_', COALESCE(table_collation, '')) <> 1
);
SET @sql = IF(@needs > 0,
    'ALTER TABLE vancepay_police_tickets CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Safe additive migrations for older schemas.

-- Stores
SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_stores'
        AND column_name = 'archived_at'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_stores ADD COLUMN archived_at TIMESTAMP NULL DEFAULT NULL AFTER updated_at',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_stores'
        AND column_name = 'status'
        AND column_type LIKE '%archived%'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_stores MODIFY COLUMN status ENUM(''active'', ''archived'') NOT NULL DEFAULT ''active''',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_stores'
        AND index_name = 'idx_owner_status'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_stores ADD INDEX idx_owner_status (owner_citizenid, status)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_stores'
        AND column_name = 'settlement_mode'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_stores ADD COLUMN settlement_mode ENUM(''store_balance'', ''public_account'') NOT NULL DEFAULT ''store_balance'' AFTER balance',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_stores'
        AND column_name = 'settlement_account_identifier'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_stores ADD COLUMN settlement_account_identifier VARCHAR(100) DEFAULT NULL AFTER settlement_mode',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_stores'
        AND column_name = 'commission_rate'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_stores ADD COLUMN commission_rate DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER settlement_account_identifier',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_stores'
        AND column_name = 'tax_rate'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_stores ADD COLUMN tax_rate DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER commission_rate',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_stores'
        AND column_name = 'tax_exempt'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_stores ADD COLUMN tax_exempt TINYINT(1) NOT NULL DEFAULT 0 AFTER tax_rate',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @add_tax_custom_rate_enabled = (
    SELECT IF(COUNT(*) = 0, 1, 0)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_stores'
        AND column_name = 'tax_custom_rate_enabled'
);
SET @sql = IF(@add_tax_custom_rate_enabled = 1,
    'ALTER TABLE vancepay_stores ADD COLUMN tax_custom_rate_enabled TINYINT(1) NOT NULL DEFAULT 0 AFTER tax_exempt',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql = IF(@add_tax_custom_rate_enabled = 1,
    'UPDATE vancepay_stores SET tax_custom_rate_enabled = 1 WHERE tax_rate > 0',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_stores'
        AND column_name = 'tax_settlement_mode'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_stores ADD COLUMN tax_settlement_mode ENUM(''store_balance'', ''public_account'') NOT NULL DEFAULT ''store_balance'' AFTER tax_custom_rate_enabled',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_stores'
        AND column_name = 'tax_settlement_account_identifier'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_stores ADD COLUMN tax_settlement_account_identifier VARCHAR(100) DEFAULT NULL AFTER tax_settlement_mode',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_stores'
        AND column_name = 'settlement_mode'
        AND column_type LIKE '%public_account%'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_stores MODIFY COLUMN settlement_mode ENUM(''store_balance'', ''public_account'') NOT NULL DEFAULT ''store_balance''',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_stores'
        AND column_name = 'tax_settlement_mode'
        AND column_type LIKE '%public_account%'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_stores MODIFY COLUMN tax_settlement_mode ENUM(''store_balance'', ''public_account'') NOT NULL DEFAULT ''store_balance''',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Employees
SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_employees'
        AND column_name = 'can_discount'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_employees ADD COLUMN can_discount TINYINT(1) NOT NULL DEFAULT 0 AFTER can_refund',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_employees'
        AND column_name = 'employee_source'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_employees ADD COLUMN employee_source ENUM(''manual'', ''public_account_sync'') NOT NULL DEFAULT ''manual'' AFTER can_discount',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_employees'
        AND column_name = 'employee_source'
        AND column_type LIKE '%public_account_sync%'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_employees MODIFY COLUMN employee_source ENUM(''manual'', ''public_account_sync'') NOT NULL DEFAULT ''manual''',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_employees'
        AND column_name = 'employee_source_key'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_employees ADD COLUMN employee_source_key VARCHAR(100) DEFAULT NULL AFTER employee_source',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_employees'
        AND index_name = 'idx_store_employee_source'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_employees ADD INDEX idx_store_employee_source (store_id, employee_source, employee_source_key)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Terminals
SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_terminals'
        AND column_name = 'type'
        AND column_type LIKE '%fixed%'
        AND column_type LIKE '%portable%'
        AND column_type LIKE '%tablet%'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_terminals MODIFY COLUMN type ENUM(''fixed'', ''portable'', ''tablet'') NOT NULL',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_terminals'
        AND column_name = 'status'
        AND column_type LIKE '%disabled%'
        AND column_type LIKE '%archived%'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_terminals MODIFY COLUMN status ENUM(''active'', ''disabled'', ''archived'') NOT NULL DEFAULT ''active''',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_terminals'
        AND column_name = 'model_key'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_terminals ADD COLUMN model_key VARCHAR(50) DEFAULT NULL AFTER status',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_terminals'
        AND column_name = 'coords'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_terminals ADD COLUMN coords JSON DEFAULT NULL AFTER model_key',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_terminals'
        AND column_name = 'heading'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_terminals ADD COLUMN heading DECIMAL(6,2) DEFAULT NULL AFTER coords',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_terminals'
        AND column_name = 'created_by_citizenid'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_terminals ADD COLUMN created_by_citizenid VARCHAR(50) DEFAULT NULL AFTER heading',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_terminals'
        AND column_name = 'archived_at'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_terminals ADD COLUMN archived_at TIMESTAMP NULL DEFAULT NULL AFTER updated_at',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_terminals'
        AND index_name = 'idx_store_type_status'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_terminals ADD INDEX idx_store_type_status (store_id, type, status)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Terminal models
SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_terminal_models'
        AND column_name = 'archived_at'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_terminal_models ADD COLUMN archived_at TIMESTAMP NULL DEFAULT NULL AFTER updated_at',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Balance entries
SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_balance_entries'
        AND column_name = 'reference_code'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_balance_entries ADD COLUMN reference_code VARCHAR(32) DEFAULT NULL AFTER amount',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_balance_entries'
        AND column_name = 'related_reference_code'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_balance_entries ADD COLUMN related_reference_code VARCHAR(32) DEFAULT NULL AFTER reference_code',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_balance_entries'
        AND column_name = 'store_name_snapshot'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_balance_entries ADD COLUMN store_name_snapshot VARCHAR(100) DEFAULT NULL AFTER related_reference_code',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_balance_entries'
        AND column_name = 'description'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_balance_entries ADD COLUMN description VARCHAR(255) DEFAULT NULL AFTER store_name_snapshot',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_balance_entries'
        AND column_name = 'available_at'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_balance_entries ADD COLUMN available_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER description',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_balance_entries'
        AND column_name = 'entry_type'
        AND column_type LIKE '%commission_refund%'
        AND column_type LIKE '%withdrawal%'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_balance_entries MODIFY COLUMN entry_type ENUM(''commission'', ''commission_refund'', ''withdrawal'') NOT NULL',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_balance_entries'
        AND index_name = 'idx_citizen_available'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_balance_entries ADD INDEX idx_citizen_available (citizenid, available_at, created_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_balance_entries'
        AND index_name = 'idx_reference'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_balance_entries ADD INDEX idx_reference (reference_code, related_reference_code)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_balance_entries'
        AND index_name = 'idx_store_time'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_balance_entries ADD INDEX idx_store_time (store_id, created_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Loans and collections
SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_loans'
        AND column_name = 'overdue_at'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_loans ADD COLUMN overdue_at TIMESTAMP NULL DEFAULT NULL AFTER due_at',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_loans'
        AND column_name = 'overdue_processed_at'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_loans ADD COLUMN overdue_processed_at TIMESTAMP NULL DEFAULT NULL AFTER overdue_at',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_loans'
        AND column_name = 'ctifo_credit_event_id'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_loans ADD COLUMN ctifo_credit_event_id INT UNSIGNED DEFAULT NULL AFTER overdue_processed_at',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_loans'
        AND index_name = 'idx_overdue_processing'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_loans ADD INDEX idx_overdue_processing (status, due_at, overdue_processed_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_loans'
        AND index_name = 'idx_ctifo_credit_event'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_loans ADD INDEX idx_ctifo_credit_event (ctifo_credit_event_id)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_collection_tasks'
        AND column_name = 'reward_rate'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_collection_tasks ADD COLUMN reward_rate DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER outstanding_amount',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_collection_tasks'
        AND column_name = 'reward_amount'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_collection_tasks ADD COLUMN reward_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER reward_rate',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_collection_tasks'
        AND column_name = 'reward_claimed_at'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_collection_tasks ADD COLUMN reward_claimed_at TIMESTAMP NULL DEFAULT NULL AFTER completed_at',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_collection_tasks'
        AND index_name = 'uk_collection_loan'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_collection_tasks ADD UNIQUE KEY uk_collection_loan (loan_id)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_collection_tasks'
        AND index_name = 'idx_collection_status'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_collection_tasks ADD INDEX idx_collection_status (status, created_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_collection_tasks'
        AND index_name = 'idx_collection_debtor'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_collection_tasks ADD INDEX idx_collection_debtor (debtor_citizenid, status)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_collection_tasks'
        AND index_name = 'idx_collection_claimed'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_collection_tasks ADD INDEX idx_collection_claimed (claimed_by_citizenid, status, claimed_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Payment intents
SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND column_name = 'status'
        AND column_type LIKE '%awaiting_customer%'
        AND column_type LIKE '%awaiting_swipe%'
        AND column_type LIKE '%completed%'
        AND column_type LIKE '%cancelled%'
        AND column_type LIKE '%expired%'
        AND column_type LIKE '%failed%'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents MODIFY COLUMN status ENUM(''pending'', ''awaiting_customer'', ''awaiting_swipe'', ''completed'', ''cancelled'', ''expired'', ''failed'') NOT NULL DEFAULT ''pending''',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND column_name = 'completed_at'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD COLUMN completed_at TIMESTAMP NULL DEFAULT NULL AFTER expires_at',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND column_name = 'item_description'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD COLUMN item_description VARCHAR(255) DEFAULT NULL AFTER target_citizenid',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND column_name = 'item_lines'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD COLUMN item_lines JSON DEFAULT NULL AFTER item_description',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND column_name = 'tax_rate'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD COLUMN tax_rate DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER fee_amount',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND column_name = 'tax_exempt'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD COLUMN tax_exempt TINYINT(1) NOT NULL DEFAULT 0 AFTER tax_rate',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND column_name = 'tax_amount'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD COLUMN tax_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER tax_exempt',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND column_name = 'commission_rate'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD COLUMN commission_rate DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER tax_amount',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND column_name = 'commission_amount'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD COLUMN commission_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER commission_rate',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND column_name = 'tax_settlement_mode'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD COLUMN tax_settlement_mode ENUM(''store_balance'', ''public_account'') NOT NULL DEFAULT ''store_balance'' AFTER commission_amount',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND column_name = 'tax_settlement_mode'
        AND column_type LIKE '%public_account%'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents MODIFY COLUMN tax_settlement_mode ENUM(''store_balance'', ''public_account'') NOT NULL DEFAULT ''store_balance''',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND column_name = 'tax_settlement_account_identifier'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD COLUMN tax_settlement_account_identifier VARCHAR(100) DEFAULT NULL AFTER tax_settlement_mode',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND index_name = 'idx_target_status'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD INDEX idx_target_status (target_citizenid, status, expires_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND index_name = 'idx_terminal_status'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD INDEX idx_terminal_status (terminal_id, status, id)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND index_name = 'idx_status_expires'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD INDEX idx_status_expires (status, expires_at, id)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND index_name = 'idx_store_status'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD INDEX idx_store_status (store_id, status)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_payment_intents'
        AND index_name = 'idx_store_created'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_payment_intents ADD INDEX idx_store_created (store_id, created_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Transactions
SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'status'
        AND column_type LIKE '%partially_refunded%'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions MODIFY COLUMN status ENUM(''completed'', ''partially_refunded'', ''refunded'') NOT NULL DEFAULT ''completed''',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'refunded_final_amount'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD COLUMN refunded_final_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER net_amount',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'refunded_net_amount'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD COLUMN refunded_net_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER refunded_final_amount',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'refunded_tax_amount'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD COLUMN refunded_tax_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER refunded_net_amount',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'refunded_commission_amount'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD COLUMN refunded_commission_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER refunded_tax_amount',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'item_description'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD COLUMN item_description VARCHAR(255) DEFAULT NULL AFTER terminal_serial_snapshot',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'item_lines'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD COLUMN item_lines JSON DEFAULT NULL AFTER item_description',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'tax_rate'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD COLUMN tax_rate DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER fee_amount',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'tax_exempt'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD COLUMN tax_exempt TINYINT(1) NOT NULL DEFAULT 0 AFTER tax_rate',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'tax_amount'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD COLUMN tax_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER tax_exempt',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'commission_rate'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD COLUMN commission_rate DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER tax_amount',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'commission_amount'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD COLUMN commission_amount DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER commission_rate',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'tax_settlement_mode'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD COLUMN tax_settlement_mode ENUM(''store_balance'', ''public_account'') NOT NULL DEFAULT ''store_balance'' AFTER commission_amount',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'tax_settlement_mode'
        AND column_type LIKE '%public_account%'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions MODIFY COLUMN tax_settlement_mode ENUM(''store_balance'', ''public_account'') NOT NULL DEFAULT ''store_balance''',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND column_name = 'tax_settlement_account_identifier'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD COLUMN tax_settlement_account_identifier VARCHAR(100) DEFAULT NULL AFTER tax_settlement_mode',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND index_name = 'idx_store_time'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD INDEX idx_store_time (store_id, created_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND index_name = 'idx_customer_time'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD INDEX idx_customer_time (customer_citizenid, created_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_transactions'
        AND index_name = 'idx_original_tx'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_transactions ADD INDEX idx_original_tx (original_tx_id)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Audit logs
SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_audit_logs'
        AND column_name = 'terminal_id'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_audit_logs ADD COLUMN terminal_id INT DEFAULT NULL AFTER store_id',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_audit_logs'
        AND column_name = 'detail'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_audit_logs ADD COLUMN detail JSON DEFAULT NULL AFTER target_id',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_audit_logs'
        AND index_name = 'idx_store_time'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_audit_logs ADD INDEX idx_store_time (store_id, created_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_audit_logs'
        AND index_name = 'idx_actor_time'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_audit_logs ADD INDEX idx_actor_time (actor_citizenid, created_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Police tickets
SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_police_tickets'
        AND column_name = 'ticket_type'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_police_tickets ADD COLUMN ticket_type VARCHAR(24) NOT NULL DEFAULT ''notice'' AFTER reason',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_police_tickets'
        AND column_name = 'ticket_style'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_police_tickets ADD COLUMN ticket_style VARCHAR(24) NOT NULL DEFAULT ''aged'' AFTER ticket_type',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_police_tickets'
        AND column_name = 'ticket_agency'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_police_tickets ADD COLUMN ticket_agency VARCHAR(32) NOT NULL DEFAULT ''lspd'' AFTER ticket_style',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_police_tickets'
        AND column_name = 'ctifo_credit_event_id'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_police_tickets ADD COLUMN ctifo_credit_event_id INT UNSIGNED DEFAULT NULL AFTER status',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_police_tickets'
        AND column_name = 'ctifo_credit_impact'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_police_tickets ADD COLUMN ctifo_credit_impact INT NOT NULL DEFAULT 0 AFTER ctifo_credit_event_id',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_police_tickets'
        AND column_name = 'paid_at'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_police_tickets ADD COLUMN paid_at TIMESTAMP NULL DEFAULT NULL AFTER ctifo_credit_impact',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_police_tickets'
        AND column_name = 'updated_at'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_police_tickets ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_police_tickets'
        AND index_name = 'idx_ticket_target_status'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_police_tickets ADD INDEX idx_ticket_target_status (target_citizenid, status, created_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_police_tickets'
        AND index_name = 'idx_ticket_officer_time'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_police_tickets ADD INDEX idx_ticket_officer_time (officer_citizenid, created_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_police_tickets'
        AND index_name = 'idx_ticket_agency_status_time'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_police_tickets ADD INDEX idx_ticket_agency_status_time (ticket_agency, status, created_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_police_tickets'
        AND index_name = 'idx_ticket_status_time'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_police_tickets ADD INDEX idx_ticket_status_time (status, created_at)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @needs = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
        AND table_name = 'vancepay_police_tickets'
        AND index_name = 'idx_ticket_ctifo_event'
);
SET @sql = IF(@needs = 0,
    'ALTER TABLE vancepay_police_tickets ADD INDEX idx_ticket_ctifo_event (ctifo_credit_event_id)',
    'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Backfill refund summary fields so reports and refund status are immediately correct.
UPDATE vancepay_transactions payment
LEFT JOIN (
    SELECT
        original_tx_id,
        COALESCE(SUM(final_amount), 0) AS refunded_final_amount,
        COALESCE(SUM(net_amount), 0) AS refunded_net_amount,
        COALESCE(SUM(tax_amount), 0) AS refunded_tax_amount,
        COALESCE(SUM(commission_amount), 0) AS refunded_commission_amount
    FROM vancepay_transactions
    WHERE type = 'refund'
        AND original_tx_id IS NOT NULL
    GROUP BY original_tx_id
) refunds ON refunds.original_tx_id = payment.id
SET payment.refunded_final_amount = COALESCE(refunds.refunded_final_amount, 0),
    payment.refunded_net_amount = COALESCE(refunds.refunded_net_amount, 0),
    payment.refunded_tax_amount = COALESCE(refunds.refunded_tax_amount, 0),
    payment.refunded_commission_amount = COALESCE(refunds.refunded_commission_amount, 0),
    payment.status = CASE
        WHEN COALESCE(refunds.refunded_final_amount, 0) >= payment.final_amount THEN 'refunded'
        WHEN COALESCE(refunds.refunded_final_amount, 0) > 0 THEN 'partially_refunded'
        ELSE 'completed'
    END
WHERE payment.type = 'payment';
