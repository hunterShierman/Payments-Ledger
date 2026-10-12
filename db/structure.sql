SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id bigint NOT NULL,
    currency character varying NOT NULL,
    balance_cents bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounts_id_seq OWNED BY public.accounts.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ledger_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ledger_entries (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    transfer_id bigint NOT NULL,
    amount_cents bigint NOT NULL,
    currency character varying NOT NULL,
    entry_type character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT ledger_entries_amount_cents_nonzero CHECK ((amount_cents <> 0))
);


--
-- Name: ledger_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ledger_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ledger_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ledger_entries_id_seq OWNED BY public.ledger_entries.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transfers (
    id bigint NOT NULL,
    source_account_id bigint NOT NULL,
    destination_account_id bigint NOT NULL,
    amount_cents bigint NOT NULL,
    currency character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    request_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT transfers_amount_cents_positive CHECK ((amount_cents > 0)),
    CONSTRAINT transfers_source_and_destination_different CHECK ((source_account_id <> destination_account_id))
);


--
-- Name: transfers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.transfers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transfers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.transfers_id_seq OWNED BY public.transfers.id;


--
-- Name: accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts ALTER COLUMN id SET DEFAULT nextval('public.accounts_id_seq'::regclass);


--
-- Name: ledger_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries ALTER COLUMN id SET DEFAULT nextval('public.ledger_entries_id_seq'::regclass);


--
-- Name: transfers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers ALTER COLUMN id SET DEFAULT nextval('public.transfers_id_seq'::regclass);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: ledger_entries ledger_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: transfers transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_pkey PRIMARY KEY (id);


--
-- Name: idx_on_source_account_id_destination_account_id_28e4e82bad; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_source_account_id_destination_account_id_28e4e82bad ON public.transfers USING btree (source_account_id, destination_account_id);


--
-- Name: index_ledger_entries_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_entries_on_account_id ON public.ledger_entries USING btree (account_id);


--
-- Name: index_ledger_entries_on_account_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_entries_on_account_id_and_created_at ON public.ledger_entries USING btree (account_id, created_at);


--
-- Name: index_ledger_entries_on_transfer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_entries_on_transfer_id ON public.ledger_entries USING btree (transfer_id);


--
-- Name: index_transfers_on_destination_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_transfers_on_destination_account_id ON public.transfers USING btree (destination_account_id);


--
-- Name: index_transfers_on_source_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_transfers_on_source_account_id ON public.transfers USING btree (source_account_id);


--
-- Name: ledger_entries fk_rails_95dd992850; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT fk_rails_95dd992850 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: transfers fk_rails_a25903a37d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT fk_rails_a25903a37d FOREIGN KEY (source_account_id) REFERENCES public.accounts(id);


--
-- Name: transfers fk_rails_c234e54e9c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT fk_rails_c234e54e9c FOREIGN KEY (destination_account_id) REFERENCES public.accounts(id);


--
-- Name: ledger_entries fk_rails_f33b502f5a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT fk_rails_f33b502f5a FOREIGN KEY (transfer_id) REFERENCES public.transfers(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261011230000'),
('20261011220854'),
('20261011220853'),
('20261011220852');

