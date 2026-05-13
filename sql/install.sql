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
