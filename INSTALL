1. Install the dependencies (PostgreSQL 9.5 and up, temporal_tables) (see below)
2. Look for the directory of the extensions
   ("/usr/local/pgsql/share/extension/" under most platforms),
   where the other extensions (e.g. temporal_tables) were installed,
   enter this directory,
   and extract the files
   (datable.control, datable--0.1.sql, datable.types).
3. Under psql, and with the right permissions, run the following command:
           CREATE EXTENSION datable;
   (the other users should not run it too)
   
##Installing the dependencies:
0.1. For PostgreSQL (9.5 and up), go to:
           [https://www.postgresql.org](https://www.postgresql.org)
0.2. For temporal_tables, go to:
           [http://pgxn.org/dist/temporal_tables](http://pgxn.org/dist/temporal_tables)
     and follow the instructions.
     Note: the following command is not needed, it's automatically run by DaTableSQL:
           CREATE EXTENSION temporal_tables;
