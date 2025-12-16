-- Remove transformed columns (original data preserved)
ALTER TABLE products DROP COLUMN price_display;
ALTER TABLE products DROP COLUMN price_dollars;

