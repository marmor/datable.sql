SET dTbGlobal.in_recurs to 0;

CREATE OR REPLACE FUNCTION on_columns_delete() RETURNS TRIGGER AS $$
BEGIN
RAISE NOTICE '-> on_columns_delete(%.%): RELNAME=%,TABLE_NAME=%,TABLE_SCHEMA=%,NARGS=% (depth=%)', OLD._table, OLD.name, TG_RELNAME, TG_TABLE_NAME, TG_TABLE_SCHEMA, TG_NARGS, pg_trigger_depth();
  IF (pg_trigger_depth() = 1 AND current_setting('dTbGlobal.in_recurs') = '0') THEN
    EXECUTE 'ALTER TABLE ' || OLD._table || ' DROP COLUMN ' || OLD.name;
  END IF;
RAISE NOTICE '<- on_columns_delete';
  RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION load_temporal() RETURNS void AS $$
DECLARE
  dir TEXT;
BEGIN
  SELECT setting INTO dir FROM pg_settings WHERE name = 'data_directory';
  dir := dir || '/../share/extension/datable.types'; -- yuck, must be better way

  CREATE EXTENSION IF NOT EXISTS temporal_tables;

  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = 'dTbTables') THEN
    CREATE TABLE dTbTables (
      name TEXT PRIMARY KEY,
      is_temporal BOOLEAN DEFAULT TRUE
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = 'dTbColumnTypes') THEN
    CREATE TABLE dTbColumnTypes (
      name TEXT PRIMARY KEY,
      alias TEXT REFERENCES dTbColumnTypes,
      parameters SMALLINT,
      is_standard BOOLEAN
    );
-- Parameter of "TIME[STAMP] WITH[OUT] TIME ZONE" must be handled explicitly!
-- In addition, currently only the 2nd parameter of INTERVAL is supported
--     ( https://www.postgresql.org/docs/9.6/static/datatype-datetime.html )
    EXECUTE 'COPY dTbColumnTypes (name, alias, parameters, is_standard)
             FROM ''' || dir || '''';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = 'dTbColumns') THEN
    CREATE TYPE dTbKeyType AS ENUM ('PRIMARY KEY', 'UNIQUE', 'NOT NULL', '');
    CREATE TABLE dTbColumns (
      name TEXT,
      column_id SERIAL UNIQUE,
      attnum SMALLINT,
      _type TEXT REFERENCES dTbColumnTypes,
      _length SMALLINT,
      _default TEXT,
      key_type dTbKeyType,
      _table TEXT REFERENCES dTbTables,
      _reference TEXT REFERENCES dTbTables,
      max_size SMALLINT,
      recommended_size SMALLINT,
      recommended_width SMALLINT,
      editable BOOLEAN DEFAULT TRUE,
      header TEXT,
      PRIMARY KEY (_table,name),
      UNIQUE (_table,attnum)
    );
    CREATE TRIGGER on_columns_delete BEFORE DELETE ON dTbColumns
      FOR EACH ROW EXECUTE PROCEDURE on_columns_delete();
  END IF;
-- TODO: CREATE TYPE tag & code & order
END;
$$ LANGUAGE 'plpgsql';

SELECT load_temporal();

CREATE OR REPLACE FUNCTION dTbNewTable(tbl TEXT) RETURNS void AS $$
DECLARE
  seq TEXT := '__' || tbl || '_seq';
BEGIN
  EXECUTE 'CREATE SEQUENCE ' || seq;
  EXECUTE 'ALTER TABLE ' || tbl ||
    ' ADD COLUMN dTbSysPeriod tstzrange NOT NULL
          DEFAULT tstzrange(current_timestamp, null),
      ADD COLUMN dTbModifier text DEFAULT SESSION_USER,
      ADD COLUMN dTbDescription text,
      ADD COLUMN dTbOrder numeric NOT NULL DEFAULT nextval(''' || seq || '''),
      ADD COLUMN dTbTag TEXT';
--    ADD COLUMN dTbTag dTbTagType';
  EXECUTE 'ALTER SEQUENCE ' || seq || ' OWNED BY ' || tbl ||'.dTbOrder';
  EXECUTE 'CREATE TABLE __' || tbl || ' () INHERITS ( ' || tbl || ' )';
  EXECUTE 'CREATE TRIGGER __versioning_' || tbl ||
' BEFORE INSERT OR UPDATE OR DELETE ON ' || tbl ||
' FOR EACH ROW EXECUTE PROCEDURE versioning(''dtbsysperiod'', ''__' || tbl ||
''', true)';
  EXECUTE 'INSERT INTO dTbTables VALUES ( ''' || tbl || ''' )';
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION ddlstart() RETURNS event_trigger AS $$
DECLARE
  e RECORD;
BEGIN
RAISE NOTICE '-> ddlstart(%,%): (depth=%)', TG_EVENT, TG_TAG, pg_trigger_depth();
  IF (pg_trigger_depth() = 0) THEN
    FOR e IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
      DECLARE
        r RECORD;
        tbl TEXT := substring(e.object_identity,8);	-- get rid of "public."
      BEGIN
RAISE NOTICE '%, %, %, %, %',
e.command_tag, e.object_type, e.schema_name, e.object_identity, e.in_extension;
        IF (substring(tbl,1,2) != '__') THEN
          FOR r IN SELECT * FROM information_schema.columns
                             WHERE table_name = tbl LOOP
            CASE e.command_tag
              WHEN 'CREATE TABLE' THEN
            ELSE
            END CASE;
          END LOOP;
        END IF;
      END;
    END LOOP;
  END IF;
-- EXCEPTION WHEN event_trigger_protocol_violated THEN
-- RAISE NOTICE '%', 'event trigger warning!';
RAISE NOTICE '<- ddlstart';
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION ddlend() RETURNS event_trigger AS $$
DECLARE
  e RECORD;
BEGIN
RAISE NOTICE '-> ddlend(%,%): (depth=%)', TG_EVENT, TG_TAG, pg_trigger_depth();
  IF (pg_trigger_depth() = 0) THEN
    FOR e IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
      DECLARE
        r RECORD;
        tbl TEXT = e.object_identity;
      BEGIN
RAISE NOTICE '%, %, %, %, %',
e.command_tag, e.object_type, e.schema_name, e.object_identity, e.in_extension;
        IF (substring(tbl,1,7) = 'public.' AND substring(tbl,8,2) != '__') THEN
          tbl := substring(tbl, 8);
          IF (e.command_tag = 'CREATE TABLE') THEN
            PERFORM dTbNewTable(tbl);
          END IF;
          FOR r IN SELECT * FROM information_schema.columns
                             WHERE table_name = tbl LOOP
            CASE e.command_tag
              WHEN 'CREATE TABLE' THEN
                EXECUTE 'INSERT INTO dTbColumns (_table,name,attnum,_type) VALUES ( ''' || tbl || ''',''' || r.column_name || ''',''' || (SELECT attnum FROM pg_attribute WHERE attname = r.column_name AND attrelid = (SELECT oid FROM pg_class WHERE relname = tbl)) || ''',''' || r.data_type || ''' )';
            ELSE
            END CASE;
          END LOOP;
        END IF;
      END;
    END LOOP;
  END IF;
RAISE NOTICE '<- ddlend';
-- Temporary, till an event filtering is set:
EXCEPTION WHEN event_trigger_protocol_violated THEN
RAISE NOTICE 'event trigger warning!';
RAISE NOTICE '<- ddlend';
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION sqldrop() RETURNS event_trigger AS $$
DECLARE
  e RECORD;
BEGIN
RAISE NOTICE '-> sqldrop(%,%): (depth=%)', TG_EVENT, TG_TAG, pg_trigger_depth();
  IF (pg_trigger_depth() = 0) THEN
    FOR e IN SELECT * FROM pg_event_trigger_dropped_objects() LOOP
RAISE NOTICE '%,%,%,%,%,%,%', e.original, e.normal, e.is_temporary, e.object_type, e.schema_name, e.object_name, e.object_identity;
      IF (e.original='t' AND e.object_type='table' AND e.schema_name='public')
      THEN
        DECLARE
          t TEXT := e.object_name;
        BEGIN
          IF (substring(t,1,2) != '__') THEN
RAISE NOTICE '% !!!', t;
            EXECUTE 'DROP TABLE IF EXISTS __' || t;
            SET dTbGlobal.in_recurs to 1;
            EXECUTE 'DELETE FROM dTbColumns WHERE _table = ''' || t || '''';
            EXECUTE 'DELETE FROM dTbTables  WHERE  name  = ''' || t || '''';
            SET dTbGlobal.in_recurs to 0;
          END IF;
        END;
      END IF;
    END LOOP;
  END IF;
RAISE NOTICE '<- sqldrop';
END;
$$ LANGUAGE 'plpgsql';

CREATE EVENT TRIGGER ddlstart ON ddl_command_start EXECUTE PROCEDURE ddlstart();
CREATE EVENT TRIGGER ddlend ON ddl_command_end EXECUTE PROCEDURE ddlend();
CREATE EVENT TRIGGER sqldrop ON sql_drop EXECUTE PROCEDURE sqldrop();
-- CREATE EVENT TRIGGER ddlend ON ddl_command_end WHEN tag IN ('create table') EXECUTE PROCEDURE ddlend();
-- CREATE EVENT TRIGGER sqldrop ON sql_drop WHEN tag IN ('drop table') EXECUTE PROCEDURE sqldrop();
