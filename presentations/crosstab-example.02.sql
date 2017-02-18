CREATE TABLE mytable(rowid text, rowdt timestamp, temperature int);
INSERT INTO mytable VALUES('test1','01 March 2003','42');
INSERT INTO mytable VALUES('test2','02 March 2003','53');
INSERT INTO mytable VALUES('test3','03 March 2003','49');

SELECT DISTINCT rowdt::date FROM mytable ORDER BY 1;

SELECT * FROM crosstab
(
  $$SELECT rowid, rowdt::date, temperature FROM mytable ORDER BY 1$$,
  $$VALUES('2003-03-01'),('2003-03-02'),('2003-03-03')$$
)
AS
(
   rowid text,
   "2003-03-01" int,
   "2003-03-02" int,
   "2003-03-03" int
);



CREATE OR REPLACE FUNCTION generate_crosstab_sql(relname text,
                                                 grpattr text,
                                                 grpattrtyp text,
                                                 catattr text,
                                                 valattr text,
                                                 valattrtyp text,
                                                 whereclause text)
RETURNS text AS $$
  DECLARE
    crosstabsql  text;
    coldef       text;
    catdef       text;
    rec      record;
  BEGIN
    coldef := '(' || grpattr || ' ' || grpattrtyp;
    catdef := 'VALUES';
    FOR rec IN EXECUTE
    'SELECT DISTINCT ' || catattr ||
    ' AS c FROM ' || relname || ' WHERE ' ||
    whereclause || ' ORDER BY 1'
    LOOP
      coldef := coldef || ',"' || rec.c || '" ' || valattrtyp;
      IF catdef = 'VALUES' THEN
        catdef := catdef || '($v$' || rec.c || '$v$)';
      ELSE
        catdef := catdef || ',($v$' || rec.c || '$v$)';
      END IF;
    END LOOP;
    coldef := coldef || ')';

    IF catdef != 'VALUES' THEN
      crosstabsql := 
      $ct$SELECT * FROM crosstab ('SELECT $ct$ ||
      grpattr || $ct$,$ct$ ||
      catattr || $ct$,$ct$ || valattr ||
      $ct$ FROM $ct$ || relname ||
      $ct$ WHERE $ct$ || whereclause ||
      $ct$ ORDER BY 1,2','$ct$ ||
      catdef || $ct$') AS $ct$ || coldef;
    END IF;
    RETURN crosstabsql;
  END;
$$ LANGUAGE plpgsql;


SELECT generate_crosstab_sql('mytable',
                             'rowid',
                             'text',
                             'rowdt::date',
                             'temperature',
                             'int',
                             '1 = 1');

SELECT * FROM crosstab
(
  $$SELECT rowid, rowdt::date, temperature FROM mytable ORDER BY 1$$,
  $$VALUES('2003-03-01'),('2003-03-02'),('2003-03-03')$$
)
AS
(
   rowid text,
   "2003-03-01" int,
   "2003-03-02" int,
   "2003-03-03" int
);



