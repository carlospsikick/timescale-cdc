-- Create schemas
CREATE SCHEMA IF NOT EXISTS dataschema;
CREATE SCHEMA IF NOT EXISTS cdc;


-- =======================
-- CDC Infrastructure
-- =======================

-- Function to track changes from any regular table as json docs
CREATE FUNCTION cdc.change_data_capture() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
		DECLARE 
		BEGIN 			
			IF TG_OP = 'UPDATE' OR TG_OP = 'INSERT' OR TG_OP = 'DELETE' then
				insert into cdc.event_log("ts", "schema_name", "table_name", "operation", "before", "after") 
				values(NOW(), TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, row_to_json(old), row_to_json(new));
				return new;	
			END IF;
		END
	$$;

-- Function to track changes from any hypertable  as json docs
CREATE FUNCTION cdc.change_data_capture_hypertable() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
        DECLARE
            schema_name text := TG_ARGV[0];
            table_name text := TG_ARGV[1];
        BEGIN
            IF TG_OP = 'UPDATE' OR TG_OP = 'INSERT' OR TG_OP = 'DELETE' then
                insert into cdc.event_log("ts", "schema_name", "table_name", "operation", "before", "after")
                values(NOW(), schema_name, table_name, TG_OP, row_to_json(old), row_to_json(new));
                return new;
            END IF;
        END
    $$;

-- Table to store event logs
CREATE TABLE cdc.event_log (
    ts timestamp with time zone NOT NULL,
    schema_name text NOT NULL,
    table_name text NOT NULL,
    operation text NOT NULL,
    before json,
    after json,
    event_id bigint NOT NULL
);

CREATE SEQUENCE cdc.event_log_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE cdc.event_log_event_id_seq OWNED BY cdc.event_log.event_id;
ALTER TABLE ONLY cdc.event_log ALTER COLUMN event_id SET DEFAULT nextval('cdc.event_log_event_id_seq'::regclass);

ALTER TABLE ONLY cdc.event_log
    ADD CONSTRAINT event_log_pkey PRIMARY KEY (event_id, ts);

-- some indexes to speed up queries
CREATE INDEX event_log_table_ts_idx ON cdc.event_log USING btree (schema_name, table_name, ts DESC, event_id);
CREATE INDEX event_log_ts_idx ON cdc.event_log USING btree (ts DESC);

-- event_log is a hypertable
DO $$ BEGIN
    PERFORM public.create_hypertable('cdc.event_log', 'ts');
    PERFORM public.add_retention_policy('cdc.event_log', INTERVAL '7 days');
END $$;

-- View to filter event logs for the assets table
CREATE VIEW cdc.event_log_assets AS
 SELECT event_log.ts,
    event_log.schema_name,
    event_log.table_name,
    event_log.operation,
    event_log.before,
    event_log.after,
    event_log.event_id
   FROM cdc.event_log
  WHERE ((event_log.schema_name = 'dataschema'::text) AND (event_log.table_name = 'assets'::text));


-- =======================
-- dataschema TABLE: assets
-- =======================
CREATE TABLE dataschema.assets (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    serialnumber TEXT UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Sample Records
INSERT INTO dataschema.assets (name, serialnumber)
VALUES 
  ('Water Pump', 'WP001'),
  ('Steam Trap', 'STM002'),
  ('Compressor', 'CMP003');

-- CDC Trigger
CREATE TRIGGER assets_cdc_tr AFTER
INSERT
    OR
DELETE
    OR
UPDATE
    ON
    dataschema.assets FOR EACH ROW EXECUTE FUNCTION cdc.change_data_capture();


-- =======================
-- dataschema TABLE: anomaly
-- =======================
CREATE TABLE dataschema.anomaly (
    ts TIMESTAMPTZ NOT NULL,
    sensorid TEXT NOT NULL,
    event JSONB NOT NULL
);

-- Make anomaly a hypertable
SELECT create_hypertable('dataschema.anomaly', 'ts');


-- sample data
INSERT INTO dataschema.anomaly (ts, sensorid, event)
VALUES
    (NOW() - INTERVAL '1 hour', 'sensor_1', '{"status": "ok"}'),
    (NOW() - INTERVAL '50 minutes', 'sensor_2', '{"status": "ok"}'),
    (NOW() - INTERVAL '40 minutes', 'sensor_3', '{"status": "ok"}'),
    (NOW() - INTERVAL '30 minutes', 'sensor_4', '{"status": "ok"}'),
    (NOW() - INTERVAL '20 minutes', 'sensor_5', '{"status": "ok"}');


-- CDC Trigger for anomaly table
CREATE TRIGGER anomaly_cdc_tr AFTER
INSERT
    OR DELETE
    OR UPDATE
    ON dataschema.anomaly
    FOR EACH ROW EXECUTE FUNCTION cdc.change_data_capture_hypertable('dataschema', 'anomaly');

