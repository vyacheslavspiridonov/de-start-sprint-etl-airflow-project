CREATE TYPE staging.status AS ENUM ('shipped','refunded'); 

ALTER TABLE staging.user_order_log 
ADD COLUMN status staging.status;

ALTER TABLE mart.f_sales 
ADD COLUMN status staging.status;


