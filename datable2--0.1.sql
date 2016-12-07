CREATE OR REPLACE FUNCTION load_temporal() RETURNS void AS
$$
DECLARE data_dir TEXT;
BEGIN
  SELECT setting into data_dir FROM pg_settings WHERE name = 'data_directory';
  data_dir := data_dir || '/../share/extension/datable.types';

--  IF ((SELECT count(*) FROM pg_extension WHERE extname = 'temporal_tables') = 0) THEN
--    CREATE EXTENSION temporal_tables;
--  END IF;
    CREATE EXTENSION IF NOT EXISTS temporal_tables;

  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = '____all_tables') THEN
    CREATE TABLE ____all_tables (
      name TEXT PRIMARY KEY,
      is_temporal BOOLEAN DEFAULT TRUE
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = '____column_types') THEN
    CREATE TABLE ____column_types (
      name TEXT PRIMARY KEY,
      alias TEXT REFERENCES ____column_types,
      parameters SMALLINT,
      is_standard BOOLEAN
    );
-- Parameter of "TIME[STAMP] WITH[OUT] TIME ZONE" must be handled explicitly!
-- In addition, currently only the 2nd parameter of INTERVAL is supported
--     ( https://www.postgresql.org/docs/9.6/static/datatype-datetime.html )
    EXECUTE 'COPY ____column_types (name, alias, parameters, is_standard) FROM ''' || data_dir || '''';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = '____all_columns') THEN
--    CREATE TYPE ____tag AS TEXT;
    CREATE TYPE ____key_type AS ENUM ('PRIMARY KEY', 'UNIQUE', 'NOT NULL', '');
    CREATE TABLE ____all_columns (
      name TEXT,
      column_id SERIAL UNIQUE,
      _type TEXT REFERENCES ____column_types,
      _length SMALLINT,
      _default TEXT,
      key_type ____key_type,
      _table TEXT REFERENCES ____all_tables,
      _reference TEXT REFERENCES ____all_tables,
      max_size SMALLINT,
      recommended_size SMALLINT,
      recommended_width SMALLINT,
      editable BOOLEAN DEFAULT TRUE,
      header TEXT,
      PRIMARY KEY (_table,name)
    );
  END IF;
-- CREATE TYPE tag & code & order
END;
$$
LANGUAGE 'plpgsql';

SELECT load_temporal();

CREATE OR REPLACE FUNCTION datableCreateTable() RETURNS event_trigger AS
$$
DECLARE
  r RECORD;
  r2 RECORD;
BEGIN
  IF (pg_trigger_depth() = 0) THEN
    FOR r IN
      SELECT * FROM pg_event_trigger_ddl_commands() LOOP
        DECLARE _r TEXT;
      BEGIN
        _r := substring(r.object_identity,8);
        IF (substring(_r,1,2) != '__') THEN
          -- RAISE NOTICE '%,%', pg_trigger_depth(), _r;
          EXECUTE 'CREATE SEQUENCE __' || _r || '_seq';
          EXECUTE 'ALTER TABLE ' || _r ||
            ' ADD COLUMN __sys_period tstzrange NOT NULL DEFAULT tstzrange(current_timestamp, null),
              ADD COLUMN __modifier text DEFAULT SESSION_USER,
              ADD COLUMN __description text,
              ADD COLUMN __order numeric NOT NULL DEFAULT nextval(''__' || _r || '_seq''),
              ADD COLUMN __tag TEXT';
--              ADD COLUMN __tag ____tag';
          EXECUTE 'ALTER  SEQUENCE __' || _r || '_seq OWNED BY ' || _r || '.__order';
          EXECUTE 'CREATE TABLE __' || _r || ' () INHERITS ( ' || _r || ' )';
          EXECUTE 'CREATE TRIGGER __versioning_' || _r || ' BEFORE INSERT OR UPDATE OR DELETE ON ' || _r || ' FOR EACH ROW EXECUTE PROCEDURE versioning(''__sys_period'', ''__' || _r ||''', true)';
          EXECUTE 'INSERT INTO ____all_tables VALUES ( ''' || _r || ''' )';
          FOR r2 IN SELECT * FROM information_schema.columns WHERE table_name = _r
          LOOP
            EXECUTE 'INSERT INTO ____all_columns (_table,name,_type) VALUES ( ''' || _r || ''',''' || r2.column_name || ''',''' || r2.data_type || ''' )';
          END LOOP;
          RAISE NOTICE '%', _r;
        END IF;
-- IF (substring(_r,1,6) != '______') THEN
        -- EXECUTE 'CREATE TABLE __' || _r || ' () INHERITS ( ' || _r || ' )';
--         RAISE NOTICE '%,%,%,%,%,%,%,%', _r,r.classid,r.objid,r.objsubid,r.command_tag,r.object_type,r.schema_name,r.in_extension;
-- IF r.command_tag = 'ALTER TABLE' THEN
-- FOR r2 IN SELECT * FROM unnest(get_altertable_subcmdtypes(r.command))
-- LOOP
-- RAISE NOTICE '  subcommand: %', r2.unnest;
-- END LOOP;
-- END IF;
-- END IF;
      END;
    END LOOP;
  END IF;
END;
$$
LANGUAGE 'plpgsql';

CREATE EVENT TRIGGER datableCreateTable ON ddl_command_end WHEN tag IN ('create table') EXECUTE PROCEDURE datableCreateTable();
