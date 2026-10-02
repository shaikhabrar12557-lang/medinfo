-- Pharma ERP schema (SQLite now, PostgreSQL-ready later)
-- Money columns are NUMERIC(12,2). Code rounds to 2 decimals.
-- Stock quantity is counted in PACKS (strips/bottles). pack_size is kept for loose selling later.
-- Dates are ISO text: 'YYYY-MM-DD'.
PRAGMA foreign_keys = ON;

------------------------------------------------------------------ SETTINGS & USERS
CREATE TABLE shop_settings (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  shop_name TEXT NOT NULL,
  address TEXT, phone TEXT,
  gstin TEXT, dl_no TEXT,
  state_code TEXT NOT NULL DEFAULT '29',          -- GST state code (29 = Karnataka)
  allow_negative_billing INTEGER NOT NULL DEFAULT 1,
  near_expiry_days INTEGER NOT NULL DEFAULT 90
);

CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('owner','pharmacist','helper')),
  is_active INTEGER NOT NULL DEFAULT 1
);

-- Bill numbers per series and financial year (SALE-B2C, SALE-B2B, PUR, SRET, PRET)
CREATE TABLE invoice_series (
  series TEXT NOT NULL,
  fin_year TEXT NOT NULL,                          -- e.g. '2026-27'
  last_no INTEGER NOT NULL DEFAULT 0,
  prefix TEXT NOT NULL,
  PRIMARY KEY (series, fin_year)
);

------------------------------------------------------------------ GST & HSN CONFIG
CREATE TABLE hsn_master (
  hsn_code TEXT PRIMARY KEY,
  description TEXT,
  gst_rate NUMERIC(5,2) NOT NULL                   -- you set and verify this with your CA
);

------------------------------------------------------------------ MASTERS
CREATE TABLE manufacturers (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

-- Shared / central catalog. Filled from a CSV import or from your own central server.
CREATE TABLE central_medicines (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  composition TEXT,
  manufacturer TEXT,
  packing TEXT,
  hsn_code TEXT,
  source TEXT NOT NULL DEFAULT 'csv',
  UNIQUE (name, packing)
);
CREATE INDEX idx_central_name ON central_medicines(name);

CREATE TABLE items (                                -- Local Item Master
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  salt TEXT,                                       -- salt / composition
  manufacturer_id INTEGER REFERENCES manufacturers(id),
  packing TEXT,                                    -- e.g. '10 TAB', '60 ML'
  pack_size INTEGER NOT NULL DEFAULT 1,
  hsn_code TEXT REFERENCES hsn_master(hsn_code),
  gst_rate NUMERIC(5,2) NOT NULL DEFAULT 12,
  schedule TEXT NOT NULL DEFAULT 'NONE' CHECK (schedule IN ('NONE','H','H1','X')),
  min_stock INTEGER NOT NULL DEFAULT 0,
  rack TEXT,
  central_id INTEGER REFERENCES central_medicines(id),
  source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','central')),
  is_verified INTEGER NOT NULL DEFAULT 1,          -- 0 = auto-imported, owner should review
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (name, packing)
);
CREATE INDEX idx_items_name ON items(name);
CREATE INDEX idx_items_salt ON items(salt);

CREATE TABLE item_barcodes (
  barcode TEXT PRIMARY KEY,
  item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE
);

CREATE TABLE suppliers (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  gstin TEXT, dl_no TEXT,
  state_code TEXT,
  phone TEXT, address TEXT,
  credit_days INTEGER NOT NULL DEFAULT 0,
  opening_balance NUMERIC(12,2) NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE customers (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT,
  gstin TEXT,                                      -- filled for B2B customers
  address TEXT,
  state_code TEXT,
  customer_type TEXT NOT NULL DEFAULT 'RETAIL' CHECK (customer_type IN ('RETAIL','B2B')),
  credit_limit NUMERIC(12,2) NOT NULL DEFAULT 0,
  opening_balance NUMERIC(12,2) NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1
);

------------------------------------------------------------------ STOCK
CREATE TABLE batches (
  id INTEGER PRIMARY KEY,
  item_id INTEGER NOT NULL REFERENCES items(id),
  batch_no TEXT NOT NULL,                          -- 'NEG' = negative billing placeholder
  expiry_date TEXT NOT NULL,
  mrp NUMERIC(12,2) NOT NULL,
  purchase_rate NUMERIC(12,2) NOT NULL DEFAULT 0,
  sale_rate NUMERIC(12,2) NOT NULL,                -- selling price (usually MRP or less)
  qty NUMERIC(12,2) NOT NULL DEFAULT 0,            -- may go below 0 only for batch_no 'NEG'
  supplier_id INTEGER REFERENCES suppliers(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (item_id, batch_no, mrp)
);
CREATE INDEX idx_batches_fefo ON batches(item_id, expiry_date);

-- Buy X get Y free, or % / flat discount, per item or per supplier
CREATE TABLE schemes (
  id INTEGER PRIMARY KEY,
  item_id INTEGER REFERENCES items(id),
  supplier_id INTEGER REFERENCES suppliers(id),
  scheme_type TEXT NOT NULL CHECK (scheme_type IN ('FREE_QTY','PERCENT','FLAT')),
  buy_qty INTEGER, free_qty INTEGER,
  discount_value NUMERIC(10,2),
  valid_from TEXT, valid_to TEXT,
  is_active INTEGER NOT NULL DEFAULT 1
);

-- Every stock movement is logged here. This is the audit trail.
CREATE TABLE stock_ledger (
  id INTEGER PRIMARY KEY,
  batch_id INTEGER NOT NULL REFERENCES batches(id),
  item_id INTEGER NOT NULL REFERENCES items(id),
  txn_type TEXT NOT NULL CHECK (txn_type IN ('PURCHASE','SALE','SALE_RETURN','PURCHASE_RETURN','ADJUSTMENT','NEG_FIX')),
  ref_id INTEGER,
  qty_change NUMERIC(12,2) NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_ledger_batch ON stock_ledger(batch_id);

------------------------------------------------------------------ PURCHASE
CREATE TABLE purchases (
  id INTEGER PRIMARY KEY,
  entry_no TEXT NOT NULL UNIQUE,
  supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
  supplier_invoice_no TEXT NOT NULL,
  invoice_date TEXT NOT NULL,
  subtotal NUMERIC(12,2) NOT NULL,
  discount NUMERIC(12,2) NOT NULL DEFAULT 0,
  taxable NUMERIC(12,2) NOT NULL,
  cgst NUMERIC(12,2) NOT NULL DEFAULT 0,
  sgst NUMERIC(12,2) NOT NULL DEFAULT 0,
  igst NUMERIC(12,2) NOT NULL DEFAULT 0,
  round_off NUMERIC(6,2) NOT NULL DEFAULT 0,
  total NUMERIC(12,2) NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (supplier_id, supplier_invoice_no)
);

CREATE TABLE purchase_items (
  id INTEGER PRIMARY KEY,
  purchase_id INTEGER NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
  item_id INTEGER NOT NULL REFERENCES items(id),
  batch_id INTEGER NOT NULL REFERENCES batches(id),
  qty NUMERIC(12,2) NOT NULL,
  free_qty NUMERIC(12,2) NOT NULL DEFAULT 0,
  purchase_rate NUMERIC(12,2) NOT NULL,
  mrp NUMERIC(12,2) NOT NULL,
  discount_pct NUMERIC(5,2) NOT NULL DEFAULT 0,
  gst_rate NUMERIC(5,2) NOT NULL,
  taxable NUMERIC(12,2) NOT NULL,
  cgst NUMERIC(12,2) NOT NULL DEFAULT 0,
  sgst NUMERIC(12,2) NOT NULL DEFAULT 0,
  igst NUMERIC(12,2) NOT NULL DEFAULT 0,
  amount NUMERIC(12,2) NOT NULL
);

CREATE TABLE purchase_returns (
  id INTEGER PRIMARY KEY,
  return_no TEXT NOT NULL UNIQUE,
  purchase_id INTEGER REFERENCES purchases(id),
  supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
  return_date TEXT NOT NULL DEFAULT (date('now')),
  reason TEXT,                                     -- expired / damaged / wrong item
  total NUMERIC(12,2) NOT NULL
);
CREATE TABLE purchase_return_items (
  id INTEGER PRIMARY KEY,
  return_id INTEGER NOT NULL REFERENCES purchase_returns(id) ON DELETE CASCADE,
  batch_id INTEGER NOT NULL REFERENCES batches(id),
  item_id INTEGER NOT NULL REFERENCES items(id),
  qty NUMERIC(12,2) NOT NULL,
  rate NUMERIC(12,2) NOT NULL,
  gst_rate NUMERIC(5,2) NOT NULL,
  amount NUMERIC(12,2) NOT NULL
);

------------------------------------------------------------------ SALES (POS)
CREATE TABLE sales (
  id INTEGER PRIMARY KEY,
  invoice_no TEXT NOT NULL UNIQUE,
  invoice_date TEXT NOT NULL DEFAULT (date('now')),
  invoice_type TEXT NOT NULL DEFAULT 'B2C' CHECK (invoice_type IN ('B2C','B2B')),
  customer_id INTEGER REFERENCES customers(id),
  place_of_supply TEXT NOT NULL,                   -- state code, decides CGST+SGST or IGST
  doctor_name TEXT,
  payment_mode TEXT NOT NULL DEFAULT 'CASH' CHECK (payment_mode IN ('CASH','UPI','CARD','CREDIT')),
  subtotal NUMERIC(12,2) NOT NULL,                 -- before bill discount (GST inclusive)
  discount NUMERIC(12,2) NOT NULL DEFAULT 0,
  taxable NUMERIC(12,2) NOT NULL,
  cgst NUMERIC(12,2) NOT NULL DEFAULT 0,
  sgst NUMERIC(12,2) NOT NULL DEFAULT 0,
  igst NUMERIC(12,2) NOT NULL DEFAULT 0,
  round_off NUMERIC(6,2) NOT NULL DEFAULT 0,
  total NUMERIC(12,2) NOT NULL,
  paid NUMERIC(12,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','CANCELLED')),
  created_by INTEGER REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_sales_date ON sales(invoice_date);

CREATE TABLE sale_items (
  id INTEGER PRIMARY KEY,
  sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
  item_id INTEGER NOT NULL REFERENCES items(id),
  batch_id INTEGER NOT NULL REFERENCES batches(id),
  hsn_code TEXT,
  qty NUMERIC(12,2) NOT NULL,
  mrp NUMERIC(12,2) NOT NULL,
  rate NUMERIC(12,2) NOT NULL,                     -- GST inclusive selling rate
  discount_pct NUMERIC(5,2) NOT NULL DEFAULT 0,
  gst_rate NUMERIC(5,2) NOT NULL,
  taxable NUMERIC(12,2) NOT NULL,
  cgst NUMERIC(12,2) NOT NULL DEFAULT 0,
  sgst NUMERIC(12,2) NOT NULL DEFAULT 0,
  igst NUMERIC(12,2) NOT NULL DEFAULT 0,
  amount NUMERIC(12,2) NOT NULL,
  returned_qty NUMERIC(12,2) NOT NULL DEFAULT 0
);

CREATE TABLE sale_returns (
  id INTEGER PRIMARY KEY,
  return_no TEXT NOT NULL UNIQUE,
  sale_id INTEGER NOT NULL REFERENCES sales(id),
  return_date TEXT NOT NULL DEFAULT (date('now')),
  taxable NUMERIC(12,2) NOT NULL,
  cgst NUMERIC(12,2) NOT NULL DEFAULT 0,
  sgst NUMERIC(12,2) NOT NULL DEFAULT 0,
  igst NUMERIC(12,2) NOT NULL DEFAULT 0,
  total NUMERIC(12,2) NOT NULL,
  reason TEXT
);
CREATE TABLE sale_return_items (
  id INTEGER PRIMARY KEY,
  return_id INTEGER NOT NULL REFERENCES sale_returns(id) ON DELETE CASCADE,
  sale_item_id INTEGER NOT NULL REFERENCES sale_items(id),
  batch_id INTEGER NOT NULL REFERENCES batches(id),
  qty NUMERIC(12,2) NOT NULL,
  amount NUMERIC(12,2) NOT NULL
);

------------------------------------------------------------------ MONEY IN / OUT, SYNC
CREATE TABLE payments (                             -- customer receipts and supplier payments
  id INTEGER PRIMARY KEY,
  party_type TEXT NOT NULL CHECK (party_type IN ('CUSTOMER','SUPPLIER')),
  party_id INTEGER NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  mode TEXT NOT NULL DEFAULT 'CASH',
  pay_date TEXT NOT NULL DEFAULT (date('now')),
  note TEXT
);

-- Offline-first: every local change is queued here and pushed to the cloud when internet is back
CREATE TABLE sync_queue (
  id INTEGER PRIMARY KEY,
  table_name TEXT NOT NULL,
  record_id INTEGER NOT NULL,
  op TEXT NOT NULL CHECK (op IN ('INSERT','UPDATE','DELETE')),
  payload TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  synced_at TEXT
);

------------------------------------------------------------------ REPORT VIEWS
CREATE VIEW v_stock AS
SELECT i.id AS item_id, i.name, i.salt, i.min_stock,
       COALESCE(SUM(CASE WHEN b.expiry_date >= date('now') THEN b.qty END), 0) AS sellable_qty,
       COALESCE(SUM(b.qty * b.purchase_rate), 0) AS stock_value
FROM items i LEFT JOIN batches b ON b.item_id = i.id
WHERE i.is_active = 1 GROUP BY i.id;

CREATE VIEW v_short_stock AS
SELECT * FROM v_stock WHERE sellable_qty <= min_stock;

CREATE VIEW v_expiry AS
SELECT b.id AS batch_id, i.name, b.batch_no, b.expiry_date, b.qty, b.mrp, b.purchase_rate,
       CAST(julianday(b.expiry_date) - julianday(date('now')) AS INTEGER) AS days_left
FROM batches b JOIN items i ON i.id = b.item_id
WHERE b.qty > 0;
