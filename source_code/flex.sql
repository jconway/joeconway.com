/*
 * flex.sql - example database implementing flexible data
 *	          collection concepts presented at OSCON2004
 *
 * Copyright (c) 2004 by Joseph E. Conway
 * ALL RIGHTS RESERVED
 * 
 * Joe Conway <mail@joeconway.com>
 * 
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without a written agreement
 * is hereby granted, provided that the above copyright notice and this
 * paragraph and the following two paragraphs appear in all copies.
 *
 * IN NO EVENT SHALL THE AUTHOR OR DISTRIBUTORS BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING
 * LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS
 * DOCUMENTATION, EVEN IF THE AUTHOR OR DISTRIBUTORS HAVE BEEN ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 * THE AUTHOR AND DISTRIBUTORS SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE AUTHOR AND DISTRIBUTORS HAS NO OBLIGATIONS TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
 */

--
-- database creation
--

BEGIN;

CREATE TABLE users (
    u_id serial NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL
) ;
ALTER TABLE  users ALTER COLUMN u_id SET NOT NULL;
ALTER TABLE  users ALTER COLUMN first_name SET NOT NULL;
ALTER TABLE  users ALTER COLUMN last_name SET NOT NULL;
ALTER TABLE users ADD CONSTRAINT users_PK PRIMARY KEY (u_id);
ALTER TABLE users ADD CONSTRAINT users_u UNIQUE (last_name, first_name);

CREATE TABLE part_master (
    pm_id serial NOT NULL,
    pm_part_number text NOT NULL,
    pm_descr text NOT NULL
) ;
ALTER TABLE  part_master ALTER COLUMN pm_id SET NOT NULL;
ALTER TABLE  part_master ALTER COLUMN pm_part_number SET NOT NULL;
ALTER TABLE  part_master ALTER COLUMN pm_descr SET NOT NULL;
ALTER TABLE part_master ADD CONSTRAINT part_master_PK PRIMARY KEY (pm_id);
ALTER TABLE part_master ADD CONSTRAINT part_master_u UNIQUE (pm_part_number);

CREATE TABLE parts (
    p_id serial NOT NULL,
    pm_id int4 NOT NULL,
    p_sn text NOT NULL,
    p_parent_p_id int4 NULL
) ;
ALTER TABLE  parts ALTER COLUMN p_id SET NOT NULL;
ALTER TABLE  parts ALTER COLUMN pm_id SET NOT NULL;
ALTER TABLE  parts ALTER COLUMN p_sn SET NOT NULL;
ALTER TABLE parts ADD CONSTRAINT parts_PK PRIMARY KEY (p_id);
ALTER TABLE parts ADD CONSTRAINT parts_u UNIQUE (pm_id, p_sn);

CREATE TABLE dataset_master (
    dm_id serial NOT NULL,
    dm_name text NOT NULL,
    pm_id int4 NOT NULL
) ;
ALTER TABLE  dataset_master ALTER COLUMN dm_id SET NOT NULL;
ALTER TABLE  dataset_master ALTER COLUMN dm_name SET NOT NULL;
ALTER TABLE  dataset_master ALTER COLUMN pm_id SET NOT NULL;
ALTER TABLE dataset_master ADD CONSTRAINT dataset_master_PK PRIMARY KEY (dm_id);
ALTER TABLE dataset_master ADD CONSTRAINT dataset_master_u UNIQUE (pm_id, dm_name);

CREATE TABLE attr_master (
    am_id serial NOT NULL,
    dm_id int4 NOT NULL,
    am_name text NOT NULL,
    am_type text NOT NULL
) ;
ALTER TABLE  attr_master ALTER COLUMN am_id SET NOT NULL;
ALTER TABLE  attr_master ALTER COLUMN dm_id SET NOT NULL;
ALTER TABLE  attr_master ALTER COLUMN am_name SET NOT NULL;
ALTER TABLE  attr_master ALTER COLUMN am_type SET NOT NULL;
ALTER TABLE attr_master ADD CONSTRAINT attr_master_PK PRIMARY KEY (am_id);
ALTER TABLE attr_master ADD CONSTRAINT attr_master_u UNIQUE (dm_id, am_name);

CREATE TABLE datasets (
    d_id serial NOT NULL,
    u_id int4 NOT NULL,
    p_id int4 NOT NULL,
    dm_id int4 NOT NULL,
    d_dts timestamptz NOT NULL
) ;
ALTER TABLE  datasets ALTER COLUMN d_id SET NOT NULL;
ALTER TABLE  datasets ALTER COLUMN u_id SET NOT NULL;
ALTER TABLE  datasets ALTER COLUMN p_id SET NOT NULL;
ALTER TABLE  datasets ALTER COLUMN dm_id SET NOT NULL;
ALTER TABLE  datasets ALTER COLUMN d_dts SET NOT NULL;
ALTER TABLE datasets ADD CONSTRAINT datasets_PK PRIMARY KEY (d_id);
ALTER TABLE datasets ADD CONSTRAINT datasets_u UNIQUE (p_id, dm_id, d_dts);

CREATE TABLE attrs (
    a_id serial NOT NULL,
    d_id int4 NOT NULL,
    am_id int4 NOT NULL,
    a_val text NULL
) ;
ALTER TABLE  attrs ALTER COLUMN a_id SET NOT NULL;
ALTER TABLE  attrs ALTER COLUMN d_id SET NOT NULL;
ALTER TABLE  attrs ALTER COLUMN am_id SET NOT NULL;
ALTER TABLE attrs ADD CONSTRAINT attrs_PK PRIMARY KEY (a_id);
ALTER TABLE attrs ADD CONSTRAINT attrs_u UNIQUE (d_id, am_id);

ALTER TABLE parts ADD CONSTRAINT parts_FK0 FOREIGN KEY (pm_id)
REFERENCES part_master (pm_id) ;
ALTER TABLE dataset_master ADD CONSTRAINT dataset_master_FK1 FOREIGN KEY (pm_id)
REFERENCES part_master (pm_id) ;
ALTER TABLE attr_master ADD CONSTRAINT attr_master_FK2 FOREIGN KEY (dm_id)
REFERENCES dataset_master (dm_id) ;
ALTER TABLE datasets ADD CONSTRAINT datasets_FK3 FOREIGN KEY (dm_id)
REFERENCES dataset_master (dm_id) ;
ALTER TABLE datasets ADD CONSTRAINT datasets_FK4 FOREIGN KEY (p_id)
REFERENCES parts (p_id) ;
ALTER TABLE datasets ADD CONSTRAINT datasets_FK5 FOREIGN KEY (u_id)
REFERENCES users (u_id) ;
ALTER TABLE attrs ADD CONSTRAINT attrs_FK6 FOREIGN KEY (d_id)
REFERENCES datasets (d_id) ;
ALTER TABLE attrs ADD CONSTRAINT attrs_FK7 FOREIGN KEY (am_id)
REFERENCES attr_master (am_id) ;
CREATE TABLE ERDESIGNER_VERSION_ID (VERSION NUMERIC(5,0) NOT NULL);
INSERT INTO ERDESIGNER_VERSION_ID (VERSION) VALUES (2);

CREATE OR REPLACE FUNCTION get_last_id(regclass, int) RETURNS int AS '
 declare
   rel    alias for $1;
   col    alias for $2;
   sql    text;
   seq    text;
   ret    record;
 begin
   select into seq (string_to_array(adsrc,''''''''))[2] from pg_attrdef where adrelid = rel::oid and adnum = col;
   sql := ''select currval('''''' || seq || '''''')::int as cur'';
   for ret in execute sql loop
     return ret.cur;
   end loop;
 end;
' LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_pm_id(text) RETURNS int AS '
 select pm_id from part_master where pm_part_number = $1
' LANGUAGE sql;

CREATE OR REPLACE FUNCTION get_u_id(text, text) RETURNS int AS '
 select u_id from users where first_name = $1 and last_name = $2
' LANGUAGE sql;

CREATE OR REPLACE FUNCTION get_dm_id(text, text) RETURNS int AS '
 select dm_id from dataset_master where dm_name = $1 and pm_id = get_pm_id($2)
' LANGUAGE sql;

CREATE OR REPLACE FUNCTION get_p_id(text, text) RETURNS int AS '
 select p_id from parts where p_sn = $1 and pm_id = get_pm_id($2)
' LANGUAGE sql;

CREATE OR REPLACE FUNCTION get_am_id(text, text, text) RETURNS int AS '
 select am_id from attr_master where am_name = $1 and dm_id = get_dm_id($2, $3)
' LANGUAGE sql;

COMMIT;

--
-- database configuration
--
BEGIN;

INSERT INTO users (u_id, first_name, last_name) VALUES (DEFAULT, 'Jim', 'Foobar');

INSERT INTO part_master(pm_id, pm_part_number, pm_descr) VALUES (DEFAULT, 'anode', 'anode used in widget');
INSERT INTO part_master(pm_id, pm_part_number, pm_descr) VALUES (DEFAULT, 'bottom', 'bottom shell of widget');
INSERT INTO part_master(pm_id, pm_part_number, pm_descr) VALUES (DEFAULT, 'top', 'top shell of widget');
INSERT INTO part_master(pm_id, pm_part_number, pm_descr) VALUES (DEFAULT, 'widget', 'widget assembly');

INSERT INTO dataset_master(dm_id, dm_name, pm_id) VALUES (DEFAULT, 'anode attrs', get_pm_id('anode'));
INSERT INTO dataset_master(dm_id, dm_name, pm_id) VALUES (DEFAULT, 'bottom attrs', get_pm_id('bottom'));
INSERT INTO dataset_master(dm_id, dm_name, pm_id) VALUES (DEFAULT, 'top attrs', get_pm_id('top'));
INSERT INTO dataset_master(dm_id, dm_name, pm_id) VALUES (DEFAULT, 'widget attrs', get_pm_id('widget'));

INSERT INTO attr_master(am_id, dm_id, am_name, am_type) VALUES (DEFAULT, get_dm_id('anode attrs', 'anode'), 'weight', 'float8');
INSERT INTO attr_master(am_id, dm_id, am_name, am_type) VALUES (DEFAULT, get_dm_id('bottom attrs', 'bottom'), 'thickness', 'float8');
INSERT INTO attr_master(am_id, dm_id, am_name, am_type) VALUES (DEFAULT, get_dm_id('top attrs', 'top'), 'thickness', 'float8');
INSERT INTO attr_master(am_id, dm_id, am_name, am_type) VALUES (DEFAULT, get_dm_id('widget attrs', 'widget'), 'height', 'float8');
INSERT INTO attr_master(am_id, dm_id, am_name, am_type) VALUES (DEFAULT, get_dm_id('widget attrs', 'widget'), 'power_out', 'float8');

COMMIT;

--
-- data collection
--

BEGIN;

-- data collection: anode
INSERT INTO parts (p_id, pm_id, p_sn, p_parent_p_id) VALUES (DEFAULT, get_pm_id('anode'), 'asn101', NULL);
INSERT INTO datasets (d_id, u_id, p_id, dm_id, d_dts) VALUES (DEFAULT, get_u_id('Jim', 'Foobar'), get_p_id('asn101', 'anode'), get_dm_id('anode attrs', 'anode'), '2004-Jun-20');
INSERT INTO attrs (a_id, d_id, am_id, a_val) VALUES (DEFAULT, get_last_id('datasets', 1), get_am_id('weight', 'anode attrs', 'anode'), 2.01);

INSERT INTO parts (p_id, pm_id, p_sn, p_parent_p_id) VALUES (DEFAULT, get_pm_id('anode'), 'asn102', NULL);
INSERT INTO datasets (d_id, u_id, p_id, dm_id, d_dts) VALUES (DEFAULT, get_u_id('Jim', 'Foobar'), get_p_id('asn102', 'anode'), get_dm_id('anode attrs', 'anode'), '2004-Jun-21');
INSERT INTO attrs (a_id, d_id, am_id, a_val) VALUES (DEFAULT, get_last_id('datasets', 1), get_am_id('weight', 'anode attrs', 'anode'), 1.97);


-- data collection: bottom
INSERT INTO parts (p_id, pm_id, p_sn, p_parent_p_id) VALUES (DEFAULT, get_pm_id('bottom'), 'bsn101', NULL);
INSERT INTO datasets (d_id, u_id, p_id, dm_id, d_dts) VALUES (DEFAULT, get_u_id('Jim', 'Foobar'), get_p_id('bsn101', 'bottom'), get_dm_id('bottom attrs', 'bottom'), '2004-Jun-20');
INSERT INTO attrs (a_id, d_id, am_id, a_val) VALUES (DEFAULT, get_last_id('datasets', 1), get_am_id('thickness', 'bottom attrs', 'bottom'), 0.756);

INSERT INTO parts (p_id, pm_id, p_sn, p_parent_p_id) VALUES (DEFAULT, get_pm_id('bottom'), 'bsn102', NULL);
INSERT INTO datasets (d_id, u_id, p_id, dm_id, d_dts) VALUES (DEFAULT, get_u_id('Jim', 'Foobar'), get_p_id('bsn102', 'bottom'), get_dm_id('bottom attrs', 'bottom'), '2004-Jun-21');
INSERT INTO attrs (a_id, d_id, am_id, a_val) VALUES (DEFAULT, get_last_id('datasets', 1), get_am_id('thickness', 'bottom attrs', 'bottom'), 0.749);

-- data collection: top
INSERT INTO parts (p_id, pm_id, p_sn, p_parent_p_id) VALUES (DEFAULT, get_pm_id('top'), 'tsn101', NULL);
INSERT INTO datasets (d_id, u_id, p_id, dm_id, d_dts) VALUES (DEFAULT, get_u_id('Jim', 'Foobar'), get_p_id('tsn101', 'top'), get_dm_id('top attrs', 'top'), '2004-Jun-20');
INSERT INTO attrs (a_id, d_id, am_id, a_val) VALUES (DEFAULT, get_last_id('datasets', 1), get_am_id('thickness', 'top attrs', 'top'), 0.754);

INSERT INTO parts (p_id, pm_id, p_sn, p_parent_p_id) VALUES (DEFAULT, get_pm_id('top'), 'tsn102', NULL);
INSERT INTO datasets (d_id, u_id, p_id, dm_id, d_dts) VALUES (DEFAULT, get_u_id('Jim', 'Foobar'), get_p_id('tsn102', 'top'), get_dm_id('top attrs', 'top'), '2004-Jun-21');
INSERT INTO attrs (a_id, d_id, am_id, a_val) VALUES (DEFAULT, get_last_id('datasets', 1), get_am_id('thickness', 'top attrs', 'top'), 0.751);

-- data collection: widget
INSERT INTO parts (p_id, pm_id, p_sn, p_parent_p_id) VALUES (DEFAULT, get_pm_id('widget'), 'wsn101', NULL);
UPDATE parts SET p_parent_p_id = get_p_id('wsn101', 'widget') WHERE p_id = get_p_id('asn101', 'anode');
UPDATE parts SET p_parent_p_id = get_p_id('wsn101', 'widget') WHERE p_id = get_p_id('bsn101', 'bottom');
UPDATE parts SET p_parent_p_id = get_p_id('wsn101', 'widget') WHERE p_id = get_p_id('tsn101', 'top');
INSERT INTO datasets (d_id, u_id, p_id, dm_id, d_dts) VALUES (DEFAULT, get_u_id('Jim', 'Foobar'), get_p_id('wsn101', 'widget'), get_dm_id('widget attrs', 'widget'), '2004-Jun-20');
INSERT INTO attrs (a_id, d_id, am_id, a_val) VALUES (DEFAULT, get_last_id('datasets', 1), get_am_id('height', 'widget attrs', 'widget'), 7.251);
INSERT INTO attrs (a_id, d_id, am_id, a_val) VALUES (DEFAULT, get_last_id('datasets', 1), get_am_id('power_out', 'widget attrs', 'widget'), 18.123);

INSERT INTO parts (p_id, pm_id, p_sn, p_parent_p_id) VALUES (DEFAULT, get_pm_id('widget'), 'wsn102', NULL);
UPDATE parts SET p_parent_p_id = get_p_id('wsn102', 'widget') WHERE p_id = get_p_id('asn102', 'anode');
UPDATE parts SET p_parent_p_id = get_p_id('wsn102', 'widget') WHERE p_id = get_p_id('bsn102', 'bottom');
UPDATE parts SET p_parent_p_id = get_p_id('wsn102', 'widget') WHERE p_id = get_p_id('tsn102', 'top');
INSERT INTO datasets (d_id, u_id, p_id, dm_id, d_dts) VALUES (DEFAULT, get_u_id('Jim', 'Foobar'), get_p_id('wsn102', 'widget'), get_dm_id('widget attrs', 'widget'), '2004-Jun-21');
INSERT INTO attrs (a_id, d_id, am_id, a_val) VALUES (DEFAULT, get_last_id('datasets', 1), get_am_id('height', 'widget attrs', 'widget'), 7.243);
INSERT INTO attrs (a_id, d_id, am_id, a_val) VALUES (DEFAULT, get_last_id('datasets', 1), get_am_id('power_out', 'widget attrs', 'widget'), 18.116);

COMMIT;

--
-- data extraction
--

select p.p_id, pm.pm_part_number from parts p join datasets d on p.p_id = d.p_id join part_master pm on p.pm_id = pm.pm_id where d.d_dts::date = '2004-Jun-20' and p.p_parent_p_id is null;

select
 pm.pm_part_number as pnum,
 (select pm_part_number from part_master join parts using (pm_id) where p_id = p.p_parent_p_id) as parent,
 p.p_sn, dm.dm_name as dset,
 u.first_name as fn,
 am.am_name as attr,
 a.a_val from
 parts p
 join part_master pm on p.pm_id = pm.pm_id
 join datasets d on p.p_id = d.p_id
 join dataset_master dm on d.dm_id = dm.dm_id
 join attrs a on d.d_id = a.d_id
 join attr_master am on a.am_id = am.am_id
 join users u on d.u_id = u.u_id
where d.d_dts::date = '2004-Jun-20';

select * from
 connectby('parts','p_id','p_parent_p_id','7',0,'~')
 AS t(p_id int, p_parent_p_id int, level int, branch text);

select pm.pm_part_number as pnum, p.p_sn, dm.dm_name as dset, u.first_name as fn, am.am_name as attr, a.a_val from
 connectby('parts','p_id','p_parent_p_id','7',0,'~')
 AS t(p_id int, p_parent_p_id int, level int, branch text)
 join parts p on t.p_id = p.p_id
 join part_master pm on p.pm_id = pm.pm_id
 join datasets d on p.p_id = d.p_id
 join dataset_master dm on d.dm_id = dm.dm_id
 join attrs a on d.d_id = a.d_id
 join attr_master am on a.am_id = am.am_id
 join users u on d.u_id = u.u_id;

select am.am_name from
 connectby('parts','p_id','p_parent_p_id','7',0,'~')
 AS t(p_id int, p_parent_p_id int, level int, branch text)
 join parts p on t.p_id = p.p_id
 join datasets d on p.p_id = d.p_id
 join attrs a on d.d_id = a.d_id
 join attr_master am on a.am_id = am.am_id
group by am.am_name;

\x
select * from crosstab(
 'select
   ''widget'' as assembly, p.p_sn,
   dm.dm_name,
   u.first_name as user_name,
   d.d_dts, pm.pm_part_number || '':'' || am.am_name,
   a.a_val
  from
   connectby(''parts'',''p_id'',''p_parent_p_id'',''7'',0,''~'')
   AS t(p_id int, p_parent_p_id int, level int, branch text)
   join parts p on t.p_id = p.p_id
   join part_master pm on p.pm_id = pm.pm_id
   join datasets d on p.p_id = d.p_id
   join dataset_master dm on d.dm_id = dm.dm_id
   join attrs a on d.d_id = a.d_id
   join attr_master am on a.am_id = am.am_id
   join users u on d.u_id = u.u_id
 ',
 '
  select
   pm.pm_part_number || '':'' || am.am_name
  from
   connectby(''parts'',''p_id'',''p_parent_p_id'',''7'',0,''~'')
   AS t(p_id int, p_parent_p_id int, level int, branch text)
   join parts p on t.p_id = p.p_id
   join part_master pm on p.pm_id = pm.pm_id
   join datasets d on p.p_id = d.p_id
   join attrs a on d.d_id = a.d_id
   join attr_master am on a.am_id = am.am_id
  group by pm.pm_part_number || '':'' || am.am_name
  order by 1
 '
) as (assembly text, sn text, dataset_name text, user_name text, dts timestamp, anode_weight float8, bottom_thickness float8, top_thickness float8, widget_height float8, widget_power_out float8);

/*
-[ RECORD 1 ]----+--------------------
assembly         | widget
sn               | wsn101
dataset_name     | widget attrs
user_name        | Jim
dts              | 2004-06-20 00:00:00
anode_weight     | 2.01
bottom_thickness | 0.756
top_thickness    | 0.754
widget_height    | 7.251
widget_power_out | 18.123
*/

CREATE OR REPLACE FUNCTION get_widget_data(timestamptz, timestamptz, text)
RETURNS setof record AS '
 declare
   start_dts alias for $1;
   end_dts   alias for $2;
   coldef    alias for $3;
   sql       text;
   rec       record;
   ret       record;
 begin
   for rec in
     select p.p_id from parts p join datasets d on p.p_id = d.p_id join part_master pm on p.pm_id = pm.pm_id where d.d_dts >= start_dts and d.d_dts <= end_dts and pm.pm_part_number = ''widget''
   loop
  
     sql := ''
     select * from crosstab(
       ''''select
         ''''''''widget'''''''' as assembly, p.p_sn,
         dm.dm_name,
         u.first_name as user_name,
         d.d_dts, pm.pm_part_number || '''''''':'''''''' || am.am_name,
         a.a_val
     from
       connectby(''''''''parts'''''''',''''''''p_id'''''''',''''''''p_parent_p_id'''''''','''''''''' || rec.p_id || '''''''''',0,''''''''~'''''''')
       AS t(p_id int, p_parent_p_id int, level int, branch text)
       join parts p on t.p_id = p.p_id
       join part_master pm on p.pm_id = pm.pm_id
       join datasets d on p.p_id = d.p_id
       join dataset_master dm on d.dm_id = dm.dm_id
       join attrs a on d.d_id = a.d_id
       join attr_master am on a.am_id = am.am_id
       join users u on d.u_id = u.u_id
     '''',
     ''''
     select
       pm.pm_part_number || '''''''':'''''''' || am.am_name
     from
       connectby(''''''''parts'''''''',''''''''p_id'''''''',''''''''p_parent_p_id'''''''','''''''''' || rec.p_id || '''''''''',0,''''''''~'''''''')
       AS t(p_id int, p_parent_p_id int, level int, branch text)
       join parts p on t.p_id = p.p_id
       join part_master pm on p.pm_id = pm.pm_id
       join datasets d on p.p_id = d.p_id
       join attrs a on d.d_id = a.d_id
       join attr_master am on a.am_id = am.am_id
     group by pm.pm_part_number || '''''''':'''''''' || am.am_name
     order by 1
     '''') as ('' || coldef || '')'';

     for ret in execute sql loop
       return next ret;
	 end loop;
   end loop;
   return;
 end;
' LANGUAGE plpgsql;

select * from get_widget_data('2004-Jun-20', '2004-Jun-21', 'assembly text, sn text, dataset_name text, user_name text, dts timestamp, anode_weight float8, bottom_thickness float8, top_thickness float8, widget_height float8, widget_power_out float8') as (assembly text, sn text, dataset_name text, user_name text, dts timestamp, anode_weight float8, bottom_thickness float8, top_thickness float8, widget_height float8, widget_power_out float8);

/*
-[ RECORD 1 ]----+--------------------
assembly         | widget
sn               | wsn101
dataset_name     | widget attrs
user_name        | Jim
dts              | 2004-06-20 00:00:00
anode_weight     | 2.01
bottom_thickness | 0.756
top_thickness    | 0.754
widget_height    | 7.251
widget_power_out | 18.123
-[ RECORD 2 ]----+--------------------
assembly         | widget
sn               | wsn102
dataset_name     | widget attrs
user_name        | Jim
dts              | 2004-06-21 00:00:00
anode_weight     | 1.97
bottom_thickness | 0.749
top_thickness    | 0.751
widget_height    | 7.243
widget_power_out | 18.116
*/

