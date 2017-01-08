SET dTbGlobal.in_recurs to 0;

CREATE OR REPLACE FUNCTION CheckDepthRecurs(depth INTEGER) RETURNS BOOLEAN AS $$
BEGIN
  IF (pg_trigger_depth() = depth) THEN
    IF (current_setting('dTbGlobal.in_recurs') = '0') THEN
      RETURN 't';
    END IF;
  END IF;
  RETURN 'f';
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION on_columns_delete() RETURNS TRIGGER AS $$
BEGIN
RAISE NOTICE '-> on_columns_delete(%.%): RELNAME=%,TABLE_NAME=%,TABLE_SCHEMA=%,NARGS=% (depth=%)', OLD._table, OLD.name, TG_RELNAME, TG_TABLE_NAME, TG_TABLE_SCHEMA, TG_NARGS, pg_trigger_depth();
  IF (CheckDepthRecurs(1)) THEN
    EXECUTE 'ALTER TABLE ' || OLD._table || ' DROP COLUMN ' || OLD.name;
  END IF;
RAISE NOTICE '<- on_columns_delete';
  RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION on_columns_update() RETURNS TRIGGER AS $$
BEGIN
RAISE NOTICE '-> on_columns_update(%.%): RELNAME=%,TABLE_NAME=%,TABLE_SCHEMA=%,NARGS=% (depth=%)', NEW._table, NEW.name, TG_RELNAME, TG_TABLE_NAME, TG_TABLE_SCHEMA, TG_NARGS, pg_trigger_depth();
  IF (CheckDepthRecurs(1)) THEN
    IF (NEW.name != OLD.name) THEN
      EXECUTE 'ALTER TABLE ' || NEW._table || ' RENAME COLUMN ' || OLD.name ||
                                                         ' TO ' || NEW.name;
    ELSEIF (NEW._type != OLD._type) THEN
      EXECUTE 'ALTER TABLE ' || NEW._table || ' ALTER COLUMN ' || NEW.name ||
           ' SET DATA TYPE ' || NEW._type  || ' USING '        || NEW.name ||
                        '::' || NEW._type;
    END IF;
  END IF;
RAISE NOTICE '<- on_columns_update';
  RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION on_columns_insert() RETURNS TRIGGER AS $$
BEGIN
RAISE NOTICE '-> on_columns_insert(%.%): RELNAME=%,TABLE_NAME=%,TABLE_SCHEMA=%,NARGS=% (depth=%)', NEW._table, NEW.name, TG_RELNAME, TG_TABLE_NAME, TG_TABLE_SCHEMA,TG_NARGS,pg_trigger_depth();
  IF (CheckDepthRecurs(1)) THEN
    EXECUTE 'ALTER TABLE ' || NEW._table || ' ADD COLUMN ' || NEW.name || ' ' ||
                              NEW._type;
    SELECT attnum INTO NEW.attnum FROM pg_attribute
                                WHERE attname = NEW.name AND attrelid =
      (SELECT oid FROM pg_class WHERE relname = NEW._table);
  END IF;
RAISE NOTICE '<- on_columns_insert';
  RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION on_tables_insert() RETURNS TRIGGER AS $$
BEGIN
RAISE NOTICE '-> on_tables_insert(%): (depth=%)', NEW.name, pg_trigger_depth();
  IF (CheckDepthRecurs(1)) THEN
    EXECUTE 'CREATE TABLE ' || NEW.name || '()';
  END IF;
RAISE NOTICE '<- on_tables_insert';
  RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION on_tables_delete() RETURNS TRIGGER AS $$
BEGIN
RAISE NOTICE '-> on_tables_delete(%): (depth=%)', OLD.name, pg_trigger_depth();
  IF (CheckDepthRecurs(1)) THEN
    EXECUTE 'DROP TABLE ' || OLD.name || ' CASCADE';
  END IF;
RAISE NOTICE '<- on_tables_delete';
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
      attnum SMALLINT DEFAULT -1,
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
    CREATE TRIGGER on_columns_update BEFORE UPDATE ON dTbColumns
      FOR EACH ROW EXECUTE PROCEDURE on_columns_update();
    CREATE TRIGGER on_columns_insert BEFORE INSERT ON dTbColumns
      FOR EACH ROW EXECUTE PROCEDURE on_columns_insert();
    CREATE TRIGGER on_tables_insert BEFORE INSERT ON dTbTables
      FOR EACH ROW EXECUTE PROCEDURE on_tables_insert();
    CREATE TRIGGER on_tables_delete BEFORE DELETE ON dTbTables
      FOR EACH ROW EXECUTE PROCEDURE on_tables_delete();
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
  IF (CheckDepthRecurs(0)) THEN
    FOR e IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
      DECLARE
        r RECORD;
        tbl TEXT := e.object_identity;
      BEGIN
RAISE NOTICE '%, %, %, %, %',
e.command_tag, e.object_type, e.schema_name, e.object_identity, e.in_extension;
        IF (substring(tbl,1,7) = 'public.' AND substring(tbl,8,2) != '__') THEN
          tbl := substring(tbl, 8);
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
  IF (CheckDepthRecurs(0)) THEN
    FOR e IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
      DECLARE
        r RECORD;
        tbl TEXT = e.object_identity;
        _type TEXT;
      BEGIN
RAISE NOTICE '%, %, %, %, %',
e.command_tag, e.object_type, e.schema_name, e.object_identity, e.in_extension;
        IF (substring(tbl,1,7) = 'public.' AND substring(tbl,8,2) != '__') THEN
          tbl := substring(tbl, 8);
          SET dTbGlobal.in_recurs to 1;
          CASE e.command_tag

            WHEN 'CREATE TABLE' THEN
              PERFORM dTbNewTable(tbl);
              FOR r IN SELECT * FROM information_schema.columns
                             WHERE table_name = tbl LOOP
                EXECUTE 'INSERT INTO dTbColumns (_table,name,attnum,_type)
                                  VALUES ( ''' || tbl || ''',''' || r.column_name || ''',''' ||
                  (SELECT attnum FROM pg_attribute
                             WHERE attname = r.column_name AND attrelid =
                    (SELECT oid  FROM pg_class WHERE relname = tbl))
                                  || ''',''' || r.data_type || ''' )';
              END LOOP;

            WHEN 'ALTER TABLE' THEN
              FOR r IN SELECT column_name FROM information_schema.columns
                     WHERE table_name = tbl EXCEPT
                         SELECT name FROM dTbColumns WHERE _table = tbl LOOP
                SELECT data_type INTO _type FROM information_schema.columns
                     WHERE table_name = tbl AND column_name = r.column_name;
RAISE NOTICE '%: %', r.column_name, _type;
                EXECUTE 'INSERT INTO dTbColumns (_table,name,attnum,_type)
                                  VALUES ( ''' || tbl || ''',''' || r.column_name || ''',''' ||
                  (SELECT attnum FROM pg_attribute
                                  WHERE attname = r.column_name AND attrelid =
                    (SELECT oid  FROM pg_class WHERE relname = tbl))
                                  || ''',''' || _type || ''' )';
              END LOOP;

              FOR r IN SELECT name FROM dTbColumns WHERE _table = tbl EXCEPT
                SELECT column_name FROM information_schema.columns
                                  WHERE table_name = tbl LOOP
RAISE NOTICE '%', r.name;
                EXECUTE 'DELETE FROM dTbColumns WHERE _table = ''' || tbl ||
                                  ''' AND name = ''' || r.name || '''';
              END LOOP;
          ELSE
          END CASE;
          SET dTbGlobal.in_recurs to 0;
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
  IF (CheckDepthRecurs(0)) THEN
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
