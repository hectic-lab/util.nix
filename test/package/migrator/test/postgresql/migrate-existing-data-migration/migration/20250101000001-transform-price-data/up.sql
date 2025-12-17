-- Add new columns and transform existing data
ALTER TABLE products ADD COLUMN price_dollars DECIMAL(10,2);
ALTER TABLE products ADD COLUMN price_display TEXT;

-- Transform existing data
UPDATE products
SET
  price_dollars = price_cents::DECIMAL / 100,
  price_display = '$' || to_char(price_cents::DECIMAL / 100, 'FM999999999.00');
