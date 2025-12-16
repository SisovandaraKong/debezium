-- init-scripts/02_create_schema.sql
ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = app_user;

-- Create sequences
CREATE SEQUENCE product_seq START WITH 1 INCREMENT BY 1;

-- Create tables
CREATE TABLE products (
    id NUMBER DEFAULT product_seq.NEXTVAL PRIMARY KEY,
    name VARCHAR2(200) NOT NULL,
    price NUMBER(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);

-- Create indexes
CREATE INDEX idx_products_name ON products(name);

-- Insert sample data
INSERT INTO products (name, price) VALUES ('Product 1', 99.99);
INSERT INTO products (name, price) VALUES ('Product 2', 149.99);
COMMIT;

-- Create or replace trigger for updating timestamp
CREATE OR REPLACE TRIGGER products_update_trigger
    BEFORE UPDATE ON products
    FOR EACH ROW
BEGIN
    :NEW.updated_at := CURRENT_TIMESTAMP;
END;
/