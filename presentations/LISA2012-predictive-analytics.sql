-- This version works with PostgreSQL 9.2.x
-------------------------------------------
-- createdb pgbench
-- pgbench -i -s 1000 pgbench
-- pgbench -c 100 -T 604800 -f /home/jconway/pgbench-custom.sql pgbench
-- watch -n 1 watchactiveconns.sh

CREATE OR REPLACE FUNCTION cache_hit_fraction() RETURNS float8 AS $$
  WITH db AS (SELECT oid FROM pg_database WHERE datname = current_database()),
  bh AS (SELECT pg_stat_get_db_blocks_hit((SELECT oid FROM db))::float8 as bh),
  bf AS (SELECT pg_stat_get_db_blocks_fetched((SELECT oid FROM db))::float8 as bf)
  SELECT 
    CASE WHEN (SELECT bf FROM bf) > 0 THEN
      ((SELECT bh FROM bh) / (SELECT bf FROM bf))::float8
    ELSE 
      0.0
    END AS cache_hit_fraction
$$ LANGUAGE sql;

CREATE EXTENSION plr;

CREATE OR REPLACE FUNCTION r_meminfo() RETURNS SETOF text AS $$
  system("cat /proc/meminfo",intern=TRUE)
$$ LANGUAGE plr;

CREATE OR REPLACE FUNCTION meminfo(OUT metric text, OUT val bigint) RETURNS SETOF record AS $$
  select trim(split_part(r_meminfo(),':',1)) as metric, split_part(trim(split_part(r_meminfo(),':',2)),' ',1)::bigint as val;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION r_iostat_c() RETURNS text AS $$
  res<-system("iostat -c",intern=TRUE)
  finres<-gsub(" +", " ", res[4])
  return(finres)
$$ LANGUAGE plr;

CREATE OR REPLACE FUNCTION iowait() RETURNS float8 AS $$
  select split_part(trim(r_iostat_c()),' ',4)::float8 as iowait;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION cpu_idle() RETURNS float8 AS $$
  select split_part(trim(r_iostat_c()),' ',6)::float8 as cpu_idle;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION r_iostat_d(
 OUT device text
,OUT tps float8
,OUT blk_read_p_s float8
,OUT blk_wrtn_p_s float8
,OUT blk_read bigint
,OUT blk_wrtn bigint
) RETURNS SETOF record AS $$
  res<-system("iostat -d",intern=TRUE)
  res<-res[4:(length(res)-1)]
  finres<-gsub(" +", " ", res)
  for (i in 1:length(finres)) {
    if (i == 1) {ffinres <- unlist(strsplit(finres[i], " "))} else {ffinres <- rbind(ffinres, unlist(strsplit(finres[i], " ")))}
  }
  fdf <-data.frame(ffinres[,1], as.numeric(ffinres[,2]), as.numeric(ffinres[,3]), as.numeric(ffinres[,4]), as.numeric(ffinres[,5]), as.numeric(ffinres[,6]))
  return(fdf)
$$ LANGUAGE plr;

CREATE OR REPLACE FUNCTION blk_read_p_s(device text) RETURNS float8 AS $$
  select blk_read_p_s FROM r_iostat_d() where device = $1;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION blk_wrtn_p_s(device text) RETURNS float8 AS $$
  select blk_wrtn_p_s FROM r_iostat_d() where device = $1;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION blk_read(device text) RETURNS bigint AS $$
  select blk_read FROM r_iostat_d() where device = $1;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION blk_wrtn(device text) RETURNS bigint AS $$
  select blk_wrtn FROM r_iostat_d() where device = $1;
$$ LANGUAGE sql;


-- assume metric id is index into single dimensional observation array
CREATE TABLE metrics (
  id int primary key,
  cum bool default false,
  metric text not null,
  sql text not null
);
CREATE UNIQUE INDEX metrics_uidx ON metrics(metric);

TRUNCATE TABLE metrics;
INSERT INTO metrics VALUES
 ( 1,DEFAULT,'active sessions','select count(1) from pg_stat_activity where state != $$idle$$ and pid != pg_backend_pid()')
,( 2,DEFAULT,'total sessions','select count(1) from pg_stat_activity')
,( 3,DEFAULT,'blocks fetched','select pg_stat_get_db_blocks_fetched((select oid from pg_database where datname = current_database()))')
,( 4,DEFAULT,'blocks hit','select pg_stat_get_db_blocks_hit((select oid from pg_database where datname = current_database()))')
,( 5,DEFAULT,'cache hit fraction','select cache_hit_fraction()')
,( 6,DEFAULT,'lock waits','select count(1) from pg_locks where not granted')
,( 7,DEFAULT,'mem free','select val from meminfo() where metric = $$MemFree$$')
,( 8,DEFAULT,'mem cached','select val from meminfo() where metric = $$Cached$$')
,( 9,DEFAULT,'swap free','select val from meminfo() where metric = $$SwapFree$$')
,(10,DEFAULT,'iowait','select iowait()')
,(11,DEFAULT,'cpu_idle','select cpu_idle()')
,(12,DEFAULT,'blk_read_p_s','select blk_read_p_s($$sdb$$)') --adjust device name for given server
,(13,DEFAULT,'blk_wrtn_p_s','select blk_wrtn_p_s($$sdb$$)') --adjust device name for given server
,(14,DEFAULT,'blk_read','select blk_read($$sdb$$)') --adjust device name for given server
,(15,DEFAULT,'blk_wrtn','select blk_wrtn($$sdb$$)') --adjust device name for given server
,(32,DEFAULT,'capture_time','')
;

CREATE TABLE measurement (
  ts timestamp without time zone primary key,
  vals float8[] not null
);

CREATE OR REPLACE FUNCTION capture_all_metrics() RETURNS float8 AS $$
  DECLARE
    rec        record;
    res        float8;
    vals       float8[];
    st         timestamp without time zone;
    et         timestamp without time zone;
  BEGIN
    st := clock_timestamp();
    FOR rec IN SELECT id, metric, sql FROM metrics WHERE id < 32 ORDER BY id LOOP
      EXECUTE rec.sql INTO res;
      vals[rec.id] := res;
    END LOOP;
    et := clock_timestamp();
    vals[32] := extract(seconds from (et - st))::float8;
    INSERT INTO measurement VALUES (st, vals);
    PERFORM pg_stat_reset();
    RETURN vals[32];
  END;
$$ LANGUAGE plpgsql;

-- this should also return how long it takes to execute as a metric
SELECT capture_all_metrics();


CREATE TABLE measurement_robj (
  ts timestamp without time zone primary key,
  samplegrp bytea not null
);

CREATE OR REPLACE FUNCTION capture_all_metrics(grpsize int, deltasecs int) RETURNS bytea AS $$
  ## Next line only used in interactive R session
  # require(RPostgreSQL)

  ## Initialize vals matrix and tms vector
  vals <- matrix(nrow = grpsize, ncol=32)
  tms <- array(dim = grpsize)

  ## Connect to Postgres database
  ## Actually a noop in PL/R
  drv <- dbDriver("PostgreSQL")
  conn <- dbConnect(drv, user="postgres", dbname="pgbench", host="localhost", port="55594")

  ## determine which metrics to collect
  sql.str <- "SELECT id, metric, sql FROM metrics WHERE id < 32 ORDER BY id"
  rec <- dbGetQuery(conn, sql.str)

  ## outer loop: perform this grpsize times
  for (grpi in 1:grpsize) {
    ## start out with a stats reset to attempt to get consistent sampling interval
    sql.str <- "SELECT 1 FROM pg_stat_reset()"
    retval <- dbGetQuery(conn, sql.str)

    ## sleep for sampling interval
    Sys.sleep(deltasecs)


    ## set this measurement start time
    st <- Sys.time()

    ## collect metric for this sample group
    for (i in 1:length(rec$id)) {
      vals[grpi, rec$id[i]] <- as.numeric(dbGetQuery(conn, rec$sql[i]))
    }

    ## set this measurement end time
    et<-Sys.time()

    ## calc time required for this sample
    vals[grpi, 32] <- difftime(et, st)

    ## save sample times
    tms[grpi] <- st

  }  ## End of outer loop

  ## Initialize sample group variable
  samplegrp <- NULL
  samplegrp$grpsize <- grpsize
  samplegrp$tms <- tms
  samplegrp$vals <- vals

  ## calculate sample group statistics
  ## first averages
  samplegrp$avgs <- apply(vals, 2, mean)
  ## second ranges
  samplegrp$rngs <- apply(vals, 2, max) - apply(vals, 2, min)

  ## Not required and noop in PL/R, but to be consistent with R session
  dbDisconnect(conn)
  dbUnloadDriver(drv)

  ## return the samplegrp R object
  return(samplegrp)

$$ LANGUAGE plr;

-- utility data extraction functions
CREATE OR REPLACE FUNCTION samplegrp_delta_ts(samplegrp bytea) RETURNS float8[] AS $$
  return(samplegrp$vals[,32])
$$ LANGUAGE plr;

CREATE OR REPLACE FUNCTION samplegrp_avgs(samplegrp bytea) RETURNS float8[] AS $$
  return(samplegrp$avgs)
$$ LANGUAGE plr;

CREATE OR REPLACE FUNCTION samplegrp_rngs(samplegrp bytea) RETURNS float8[] AS $$
  return(samplegrp$rngs)
$$ LANGUAGE plr;

CREATE OR REPLACE FUNCTION samplegrp_vals(samplegrp bytea) RETURNS float8[] AS $$
  return(samplegrp$vals)
$$ LANGUAGE plr;

SELECT ts, samplegrp_avgs(samplegrp), samplegrp_rngs(samplegrp) FROM measurement_robj ORDER by 1 DESC;
SELECT ts, samplegrp_vals(samplegrp) FROM measurement_robj ORDER by ts DESC LIMIT 30;

-------------------------------------------------------------------------------
-- new stuff starts here
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION samplegrp_init_qccvals() RETURNS int AS $$
  qccvals<<-data.frame()
  return(nrow(qccvals))
$$ LANGUAGE plr;

CREATE OR REPLACE FUNCTION samplegrp_construct_qccvals(samplegrp bytea, sampletrial int) RETURNS int AS $$
  n <- (nrow(qccvals) / samplegrp$grpsize) + 1
  if (n <= sampletrial) {
    qccvals <<- rbind(qccvals, data.frame(samplegrp$tms, samplegrp$vals, sample=n, trial=TRUE))
  } else {
    qccvals <<- rbind(qccvals, data.frame(samplegrp$tms, samplegrp$vals, sample=n, trial=FALSE))
  }
  return(n)
$$ LANGUAGE plr;

CREATE OR REPLACE FUNCTION qccvals() RETURNS SETOF RECORD AS $$
  return(qccvals)
$$ LANGUAGE plr;

SELECT samplegrp_init_qccvals();
SELECT samplegrp_construct_qccvals(touter.samplegrp, 30) FROM
  (
    SELECT tinner.ts, tinner.samplegrp FROM
    (
      SELECT ts, samplegrp FROM measurement_robj ORDER by ts DESC LIMIT 40
    ) tinner ORDER BY tinner.ts
  ) touter;

SELECT * FROM qccvals() AS qcc(
 tms float8,
 X1 float8,
 X2 float8,
 X3 float8,
 X4 float8,
 X5 float8,
 X6 float8,
 X7 float8,
 X8 float8,
 X9 float8,
 X10 float8,
 X11 float8,
 X12 float8,
 X13 float8,
 X14 float8,
 X15 float8,
 X16 float8,
 X17 float8,
 X18 float8,
 X19 float8,
 X20 float8,
 X21 float8,
 X22 float8,
 X23 float8,
 X24 float8,
 X25 float8,
 X26 float8,
 X27 float8,
 X28 float8,
 X29 float8,
 X30 float8,
 X31 float8,
 X32 float8,
 sample int,
 trial bool
);

--# crontab -l
--# m h  dom mon dow   command
--*     * * * * su - postgres -c "source /opt/src/pgsql-git/pg92; psql pgbench -c 'SELECT capture_all_metrics()'" > /dev/null
--*/3   * * * * su - postgres -c "source /opt/src/pgsql-git/pg92; psql pgbench -c 'INSERT INTO measurement_robj VALUES (current_timestamp, capture_all_metrics(3, 30))'" > /dev/null
--42  */3 * * * su - postgres -c "source /opt/src/pgsql-git/pg92; psql pgbench -c 'select * from generate_series(1,300000000)'" > /dev/null



