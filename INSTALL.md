1. Install the dependencies (PostgreSQL 9.5 and up, temporal_tables) (see below)
2. Look for the directory of the extensions<br/>
   ("/usr/local/pgsql/share/extension/" under most platforms),<br/>
   where the other extensions (e.g. temporal_tables) were installed,<br/>
   enter this directory,<br/>
   and extract the files<br/>
   (datable.control, datable--0.1.sql, datable.types).
3. Under psql, and with the right permissions, run the following command:<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CREATE EXTENSION datable;<br/>
   (the other users should not run it too)
   
##Installing the dependencies:
0.1. For PostgreSQL (9.5 and up), go to:<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[https://www.postgresql.org](https://www.postgresql.org)

0.2. For temporal_tables, go to:<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[http://pgxn.org/dist/temporal_tables](http://pgxn.org/dist/temporal_tables)<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;and follow the instructions.<br/>

Note: the following command is not needed, it's automatically run by DaTableSQL:<br/>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CREATE EXTENSION temporal_tables;
