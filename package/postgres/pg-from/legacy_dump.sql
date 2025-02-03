-- PostgreSQL database dump generated from SQLite
CREATE SCHEMA IF NOT EXISTS legacy;

SET client_encoding = 'UTF8';

CREATE TABLE legacy."promocode" (
    "promo_name" text NOT NULL,
    "traffic_amount" bigint NOT NULL,
    "remaining_activation" bigint NOT NULL,
    "term" text,
    "pool" text DEFAULT 'residential'
);

ALTER TABLE legacy."promocode" OWNER TO postgres;

CREATE TABLE legacy."user" (
    "user_id" text NOT NULL,
    "buy_num" bigint DEFAULT 0,
    "sub_id" bigint,
    "used_promo_list" text,
    "ip_list" text,
    "pool" text
);

ALTER TABLE legacy."user" OWNER TO postgres;

CREATE TABLE legacy."price" (
    "gb_cost" bigint,
    "pool" text NOT NULL DEFAULT 'residential',
    "gb_cost_usd" double precision NOT NULL DEFAULT 0
);

ALTER TABLE legacy."price" OWNER TO postgres;

CREATE TABLE legacy."all_user" (
    "user_id" text,
    "lang" text,
    "invited_by" text,
    "ref_balance" bigint NOT NULL DEFAULT 0,
    "pers_percent" text,
    "reg_date" text,
    "username" text,
    "email" text,
    "password" text,
    "role_id" bigint,
    "confirmed" bigint,
    "tgcode" text,
    "tgcode_expires" text,
    "ref_balance_usd" double precision NOT NULL DEFAULT 0
);

ALTER TABLE legacy."all_user" OWNER TO postgres;

CREATE UNIQUE INDEX idx_email ON legacy."all_user" ("email");

CREATE UNIQUE INDEX idx_username ON legacy."all_user" ("username");

CREATE TABLE legacy."admin_ref" (
    "value" text,
    "name" text,
    "number" bigint DEFAULT 0,
    "user" text
);

ALTER TABLE legacy."admin_ref" OWNER TO postgres;

CREATE TABLE legacy."disc_promocode" (
    "name" text NOT NULL,
    "discount" double precision NOT NULL,
    "activations" bigint NOT NULL,
    "first_use" text NOT NULL,
    "term" text,
    "user_for" text,
    "is_global" bigint DEFAULT 0
);

ALTER TABLE legacy."disc_promocode" OWNER TO postgres;

CREATE TABLE legacy."request" (
    "com" text,
    "amount" bigint,
    "user_id" text,
    "username" text,
    "in_id" SERIAL PRIMARY KEY
);

ALTER TABLE legacy."request" OWNER TO postgres;

CREATE TABLE legacy."system" (
    "key" text,
    "value" text
);

ALTER TABLE legacy."system" OWNER TO postgres;

CREATE TABLE legacy."banner" (
    "name" text,
    "photo_id" text,
    "link" text
);

ALTER TABLE legacy."banner" OWNER TO postgres;

CREATE TABLE legacy."subuser" (
    "sub_id" bigint,
    "owner_sub_id" bigint,
    "label" text
);

ALTER TABLE legacy."subuser" OWNER TO postgres;

CREATE TABLE legacy."reseller" (
    "user_id" text,
    "token" text,
    "sub_id" bigint
);

ALTER TABLE legacy."reseller" OWNER TO postgres;

CREATE TABLE legacy."available_pay" (
    "name" text,
    "is_available" text
);

ALTER TABLE legacy."available_pay" OWNER TO postgres;

CREATE TABLE legacy."payment" (
    "user_id" text NOT NULL,
    "subuser_id" bigint NOT NULL,
    "paid" bigint,
    "order_id" text,
    "amount_gb" bigint NOT NULL,
    "balance_before" text NOT NULL,
    "discount" text,
    "service" text NOT NULL,
    "date" text NOT NULL
);

ALTER TABLE legacy."payment" OWNER TO postgres;

CREATE TABLE legacy."temp_payment" (
    "result" text,
    "payment_id" text,
    "merchant_id" text,
    "order_id" text,
    "amount" bigint
);

ALTER TABLE legacy."temp_payment" OWNER TO postgres;

CREATE TABLE legacy."role" (
    "id" SERIAL PRIMARY KEY,
    "name" text NOT NULL
);

ALTER TABLE legacy."role" OWNER TO postgres;

CREATE TABLE legacy."promo_activations" (
    "user_id" text NOT NULL,
    "promo_name" text NOT NULL,
    "usage_count" bigint NOT NULL DEFAULT 0,
    PRIMARY KEY ("user_id", "promo_name")
);

ALTER TABLE legacy."promo_activations" OWNER TO postgres;

CREATE SEQUENCE legacy_request_seq START WITH 4 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
CREATE SEQUENCE legacy_role_seq START WITH 3 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
