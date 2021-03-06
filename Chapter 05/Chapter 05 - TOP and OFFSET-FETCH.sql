---------------------------------------------------------------------
-- T-SQL Querying (Microsoft Press, 2015)
-- Chapter 05 - TOP and OFFSET-FETCH
-- © Itzik Ben-Gan
---------------------------------------------------------------------

SET NOCOUNT ON;

---------------------------------------------------------------------
-- The TOP and OFFSET-FETCH Filters
---------------------------------------------------------------------

---------------------------------------------------------------------
-- The TOP Filter
---------------------------------------------------------------------

-- TOP with number of rows
USE TSQLV3;

SELECT TOP (3) orderid, orderdate, custid, empid
FROM Sales.Orders
ORDER BY orderdate DESC;

-- TOP with PERCENT
SELECT TOP (1) PERCENT orderid, orderdate, custid, empid
FROM Sales.Orders
ORDER BY orderdate DESC;

-- TOP without ORDER BY
SELECT TOP (3) orderid, orderdate, custid, empid
FROM Sales.Orders;

-- Determinism: TOP WITH TIES
SELECT TOP (3) WITH TIES orderid, orderdate, custid, empid
FROM Sales.Orders
ORDER BY orderdate DESC;

-- Puzzle: what is the task that the following query achieves?
SELECT TOP (1) WITH TIES orderid, orderdate, custid, empid
FROM Sales.Orders
ORDER BY ROW_NUMBER() OVER(PARTITION BY custid ORDER BY orderdate DESC, orderid DESC);

-- Determinism: Using a tiebreaker
SELECT TOP (3) orderid, orderdate, custid, empid
FROM Sales.Orders
ORDER BY orderdate DESC, orderid DESC;

-- Arbitrary order, explicit
SELECT TOP (3) orderid, orderdate, custid, empid
FROM Sales.Orders
ORDER BY (SELECT NULL);

-- Reminder: presentation order is guaranteed only if outer query has an ORDER BY clause
-- Here presentation order is not guaranteed:
SELECT orderid, orderdate, custid, empid
FROM ( SELECT TOP (3) orderid, orderdate, custid, empid
       FROM Sales.Orders
       ORDER BY orderdate DESC, orderid DESC            ) AS D;

-- Here it is guaranteed
SELECT orderid, orderdate, custid, empid
FROM ( SELECT TOP (3) orderid, orderdate, custid, empid
       FROM Sales.Orders
       ORDER BY orderdate DESC, orderid DESC            ) AS D
ORDER BY orderdate DESC, orderid DESC;

---------------------------------------------------------------------
-- The OFFSET-FETCH Filter
---------------------------------------------------------------------

-- Fetch rows 51 - 75
SELECT orderid, orderdate, custid, empid
FROM Sales.Orders
ORDER BY orderdate DESC, orderid DESC
OFFSET 50 ROWS FETCH NEXT 25 ROWS ONLY;

-- Arbitrary order
SELECT orderid, orderdate, custid, empid
FROM Sales.Orders
ORDER BY (SELECT NULL)
OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY;

-- Skip rows, but don't limit
SELECT orderid, orderdate, custid, empid
FROM Sales.Orders
ORDER BY orderdate DESC, orderid DESC
OFFSET 50 ROWS;
GO

---------------------------------------------------------------------
-- Optimization of Filters Demonstrated Through Paging
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Optimization of TOP
---------------------------------------------------------------------

-- GetPage proc, using TOP, single sort column
USE PerformanceV3;
IF OBJECT_ID(N'dbo.GetPage', N'P') IS NOT NULL DROP PROC dbo.GetPage;
GO
CREATE PROC dbo.GetPage
  @orderid  AS INT    = 0, -- anchor sort key
  @pagesize AS BIGINT = 25
AS

SELECT TOP (@pagesize) orderid, orderdate, custid, empid
FROM dbo.Orders
WHERE orderid > @orderid
ORDER BY orderid;
GO

EXEC dbo.GetPage @pagesize = 25;

EXEC dbo.GetPage @orderid = 25, @pagesize = 25;

EXEC dbo.GetPage @orderid = 50, @pagesize = 25;

-- Multiple sort columns - first predicate form
IF OBJECT_ID(N'dbo.GetPage', N'P') IS NOT NULL DROP PROC dbo.GetPage;
GO
CREATE PROC dbo.GetPage
  @orderdate AS DATE   = '00010101', -- anchor sort key 1 (orderdate)
  @orderid   AS INT    = 0,          -- anchor sort key 2 (orderid)
  @pagesize  AS BIGINT = 25
AS

SELECT TOP (@pagesize) orderid, orderdate, custid, empid
FROM dbo.Orders
WHERE orderdate >= @orderdate
  AND (orderdate > @orderdate OR orderid > @orderid)
ORDER BY orderdate, orderid;
GO

EXEC dbo.GetPage @pagesize = 25;

EXEC dbo.GetPage @orderdate = '20101207', @orderid = 410, @pagesize = 25;

EXEC dbo.GetPage @orderdate = '20101209', @orderid = 2830, @pagesize = 25;

-- Multiple sort columns - second predicate form
IF OBJECT_ID(N'dbo.GetPage', N'P') IS NOT NULL DROP PROC dbo.GetPage;
GO
CREATE PROC dbo.GetPage
  @orderdate AS DATE   = '00010101', -- anchor sort key 1 (orderdate)
  @orderid   AS INT    = 0,          -- anchor sort key 2 (orderid)
  @pagesize  AS BIGINT = 25
AS

SELECT TOP (@pagesize) orderid, orderdate, custid, empid
FROM dbo.Orders
WHERE (orderdate = @orderdate AND orderid > @orderid)
   OR orderdate > @orderdate
ORDER BY orderdate, orderid;
GO

-- Using TOP over TOP
IF OBJECT_ID(N'dbo.GetPage', N'P') IS NOT NULL DROP PROC dbo.GetPage;
GO
CREATE PROC dbo.GetPage
  @pagenum  AS BIGINT = 1,
  @pagesize AS BIGINT = 25
AS

SELECT orderdate, custid, empid
FROM ( SELECT TOP (@pagesize) *
       FROM ( SELECT TOP (@pagenum * @pagesize) *
              FROM dbo.Orders
              ORDER BY orderid ) AS D1
       ORDER BY orderid DESC ) AS D2
ORDER BY orderid;
GO

EXEC dbo.GetPage @pagenum = 1, @pagesize = 25;
EXEC dbo.GetPage @pagenum = 2, @pagesize = 25;
EXEC dbo.GetPage @pagenum = 3, @pagesize = 25;

---------------------------------------------------------------------
-- Optimization of OFFSET-FETCH
---------------------------------------------------------------------

-- Using OFFSET-FETCH
IF OBJECT_ID(N'dbo.GetPage', N'P') IS NOT NULL DROP PROC dbo.GetPage;
GO
CREATE PROC dbo.GetPage
  @pagenum  AS BIGINT = 1,
  @pagesize AS BIGINT = 25
AS

SELECT orderid, orderdate, custid, empid
FROM dbo.Orders
ORDER BY orderid
OFFSET (@pagenum - 1) * @pagesize ROWS FETCH NEXT @pagesize ROWS ONLY;
GO

EXEC dbo.GetPage @pagenum = 1, @pagesize = 25;
EXEC dbo.GetPage @pagenum = 2, @pagesize = 25;
EXEC dbo.GetPage @pagenum = 3, @pagesize = 25;

EXEC dbo.GetPage @pagenum = 1000, @pagesize = 25;
GO

-- Implementation that minimizes lookups
ALTER PROC dbo.GetPage
  @pagenum  AS BIGINT = 1,
  @pagesize AS BIGINT = 25
AS

WITH K AS
(
  SELECT orderid
  FROM dbo.Orders
  ORDER BY orderid
  OFFSET (@pagenum - 1) * @pagesize ROWS FETCH NEXT @pagesize ROWS ONLY
)
SELECT O.orderid, O.orderdate, O.custid, O.empid
FROM dbo.Orders AS O
  INNER JOIN K
    ON O.orderid = K.orderid
ORDER BY O.orderid;
GO

EXEC dbo.GetPage @pagenum = 3, @pagesize = 25;

EXEC dbo.GetPage @pagenum = 1000, @pagesize = 25;
GO

---------------------------------------------------------------------
-- Optimization of ROW_NUMBER
---------------------------------------------------------------------

-- Using ROW_NUMBER
IF OBJECT_ID(N'dbo.GetPage', N'P') IS NOT NULL DROP PROC dbo.GetPage;
GO
CREATE PROC dbo.GetPage
  @pagenum  AS BIGINT = 1,
  @pagesize AS BIGINT = 25
AS

WITH C AS
(
  SELECT orderid, orderdate, custid, empid,
    ROW_NUMBER() OVER(ORDER BY orderid) AS rn
  FROM dbo.Orders
)
SELECT orderid, orderdate, custid, empid
FROM C
WHERE rn BETWEEN (@pagenum - 1) * @pagesize + 1 AND @pagenum * @pagesize
ORDER BY rn;
GO

EXEC dbo.GetPage @pagenum = 1, @pagesize = 25;
EXEC dbo.GetPage @pagenum = 2, @pagesize = 25;
EXEC dbo.GetPage @pagenum = 3, @pagesize = 25;

EXEC dbo.GetPage @pagenum = 1000, @pagesize = 25;
GO

-- Implementation that minimizes lookups
ALTER PROC dbo.GetPage
  @pagenum  AS BIGINT = 1,
  @pagesize AS BIGINT = 25
AS

WITH C AS
(
  SELECT orderid, ROW_NUMBER() OVER(ORDER BY orderid) AS rn
  FROM dbo.Orders
),
K AS
(
  SELECT orderid, rn
  FROM C
  WHERE rn BETWEEN (@pagenum - 1) * @pagesize + 1 AND @pagenum * @pagesize
)
SELECT O.orderid, O.orderdate, O.custid, O.empid
FROM dbo.Orders AS O
  INNER JOIN K
    ON O.orderid = K.orderid
ORDER BY K.rn;
GO

EXEC dbo.GetPage @pagenum = 3, @pagesize = 25;

EXEC dbo.GetPage @pagenum = 1000, @pagesize = 25;
GO

---------------------------------------------------------------------
-- Using the TOP Option with Modifications
---------------------------------------------------------------------

-- Creating and populating the dbo.MyOrders table
USE PerformanceV3;
IF OBJECT_ID(N'dbo.MyOrders', N'U') IS NOT NULL DROP TABLE dbo.MyOrders;
GO
SELECT * INTO dbo.MyOrders FROM dbo.Orders;
CREATE UNIQUE CLUSTERED INDEX idx_od_oid ON dbo.MyOrders(orderdate, orderid);
GO

---------------------------------------------------------------------
-- TOP with Modifications
---------------------------------------------------------------------

-- DELETE with TOP
DELETE TOP (50) FROM dbo.MyOrders;

-- Controlling order
WITH C AS
(
  SELECT TOP (50) *
  FROM dbo.MyOrders
  ORDER BY orderdate, orderid
)
DELETE FROM C;

---------------------------------------------------------------------
-- Modifying in Chunks
---------------------------------------------------------------------

-- original DELETE (don't run this statement)
DELETE FROM dbo.MyOrders WHERE orderdate < '20130101';

-- Run an XEevents session / trace with lock escalation event
CREATE EVENT SESSION [Lock_Escalation] ON SERVER 
ADD EVENT sqlserver.lock_escalation(
    WHERE ([sqlserver].[session_id]=(53)));

-- Check escalation point (try different numbers)
DELETE TOP (10000) FROM dbo.MyOrders WHERE orderdate < '20130101';

-- Delete in chunks
SET NOCOUNT ON;

WHILE 1 = 1
BEGIN
  DELETE TOP (3000) FROM dbo.MyOrders WHERE orderdate < '20130101';
  IF @@ROWCOUNT < 3000 BREAK;
END
GO

---------------------------------------------------------------------
-- TOP N Per Group
---------------------------------------------------------------------

USE TSQLV3;

-- POC index
CREATE UNIQUE INDEX idx_poc ON Sales.Orders(custid, orderdate DESC, orderid DESC)
  INCLUDE(empid);

---------------------------------------------------------------------
-- Solution Using ROW_NUMBER
---------------------------------------------------------------------

-- ROW_NUMBER, POC + Low Density
WITH C AS
(
  SELECT 
    ROW_NUMBER() OVER(
      PARTITION BY custid
      ORDER BY orderdate DESC, orderid DESC) AS rownum,
    orderid, orderdate, custid, empid
  FROM Sales.Orders
)
SELECT custid, orderdate, orderid, empid
FROM C
WHERE rownum <= 3;

---------------------------------------------------------------------
-- Solution Using TOP and APPLY
---------------------------------------------------------------------

-- Single customer
SELECT TOP (3) orderid, orderdate, empid
FROM Sales.Orders
WHERE custid = 1
ORDER BY orderdate DESC, orderid DESC;

-- TOP and APPLY, POC + High Density
SELECT C.custid, A.orderid, A.orderdate, A.empid
FROM Sales.Customers AS C
  CROSS APPLY ( SELECT TOP (3) orderid, orderdate, empid
                FROM Sales.Orders AS O
                WHERE O.custid = C.custid
                ORDER BY orderdate DESC, orderid DESC ) AS A;

---------------------------------------------------------------------
-- Solution Using Concatenation
---------------------------------------------------------------------

-- Remove index
DROP INDEX idx_poc ON Sales.Orders;

-- Concatenation, no POC index + N = 1
WITH C AS
(
  SELECT
    custid,
    MAX( (CONVERT(CHAR(8), orderdate, 112)
          + RIGHT('000000000' + CAST(orderid AS VARCHAR(10)), 10)
          + CAST(empid AS CHAR(10)) ) COLLATE Latin1_General_BIN2 ) AS s
  FROM Sales.Orders
  GROUP BY custid
)
SELECT custid,
  CAST( SUBSTRING(s,  1,  8) AS DATE     ) AS orderdate,
  CAST( SUBSTRING(s,  9, 10) AS INT      ) AS orderid,
  CAST( SUBSTRING(s, 19, 10) AS CHAR(10) ) AS empid
FROM C;

-- Query plan against large table
USE PerformanceV3;

WITH C AS
(
  SELECT
    custid,
    MAX( (CONVERT(CHAR(8), orderdate, 112)
          + RIGHT('000000000' + CAST(orderid AS VARCHAR(10)), 10)
          + CAST(empid AS CHAR(10)) ) COLLATE Latin1_General_BIN2 ) AS s
  FROM dbo.Orders
  GROUP BY custid
)
SELECT custid,
  CAST( SUBSTRING(s,  1,  8) AS DATE     ) AS orderdate,
  CAST( SUBSTRING(s,  9, 10) AS INT      ) AS orderid,
  CAST( SUBSTRING(s, 19, 10) AS CHAR(10) ) AS empid
FROM C;

---------------------------------------------------------------------
-- Median
---------------------------------------------------------------------

-- Small set of sample data
USE tempdb;
IF OBJECT_ID(N'dbo.T1', N'U') IS NOT NULL DROP TABLE dbo.T1;
GO

CREATE TABLE dbo.T1
(
  id  INT NOT NULL IDENTITY
    CONSTRAINT PK_T1 PRIMARY KEY,
  grp INT NOT NULL,
  val INT NOT NULL
);

CREATE INDEX idx_grp_val ON dbo.T1(grp, val);

INSERT INTO dbo.T1(grp, val)
  VALUES(1, 30),(1, 10),(1, 100),
        (2, 65),(2, 60),(2, 65),(2, 10);
GO

-- Large set of sample data
DECLARE
  @numgroups AS INT = 10,
  @rowspergroup AS INT = 1000000;

TRUNCATE TABLE dbo.T1;

DROP INDEX idx_grp_val ON dbo.T1;

INSERT INTO dbo.T1 WITH(TABLOCK) (grp, val)
  SELECT G.n, ABS(CHECKSUM(NEWID())) % 10000000
  FROM TSQLV3.dbo.GetNums(1, @numgroups) AS G
    CROSS JOIN TSQLV3.dbo.GetNums(1, @rowspergroup) AS R;

CREATE INDEX idx_grp_val ON dbo.T1(grp, val);
GO

---------------------------------------------------------------------
-- Solution Using PERCENTILE_CONT
---------------------------------------------------------------------

SELECT DISTINCT grp, PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY val) OVER(PARTITION BY grp) AS median
FROM dbo.T1;

---------------------------------------------------------------------
-- Solution Using ROW_NUMBER
---------------------------------------------------------------------

WITH Counts AS
(
  SELECT grp, COUNT(*) AS cnt
  FROM dbo.T1
  GROUP BY grp
),
RowNums AS
(
  SELECT grp, val,
    ROW_NUMBER() OVER(PARTITION BY grp ORDER BY val) AS n
  FROM dbo.T1
)
SELECT C.grp, AVG(1. * R.val) AS median
FROM Counts AS C
  INNER MERGE JOIN RowNums AS R
    on C.grp = R.grp
WHERE R.n IN ( ( C.cnt + 1 ) / 2, ( C.cnt + 2 ) / 2 )
GROUP BY C.grp;

---------------------------------------------------------------------
-- Solution Using OFFSET-FETCH and APPLY
---------------------------------------------------------------------

WITH C AS
(
  SELECT grp,
    COUNT(*) AS cnt,
    (COUNT(*) - 1) / 2 AS ov,
    2 - COUNT(*) % 2 AS fv
  FROM dbo.T1
  GROUP BY grp
)
SELECT grp, AVG(1. * val) AS median
FROM C
  CROSS APPLY ( SELECT O.val
                FROM dbo.T1 AS O
                where O.grp = C.grp
                order by O.val
                OFFSET C.ov ROWS FETCH NEXT C.fv ROWS ONLY ) AS A
GROUP BY grp;
