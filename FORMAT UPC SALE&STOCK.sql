USE NIKE;

UPDATE SALES_DATA
SET UPC=LEFT(UPC,12) WHERE LEN(UPC)=13;

UPDATE SALES_DATA
SET UPC=CONCAT('0',UPC) WHERE LEN(UPC)=11;

UPDATE SALES_DATA
SET SALES_DATA.UPC=MASTER_UPC.UPC
FROM MASTER_UPC
WHERE LEFT(CONCAT('0',SALES_DATA.UPC),12)=MASTER_UPC.UPC;

UPDATE STOCK
SET UPC=LEFT(UPC,12) WHERE LEN(UPC)=13;

UPDATE STOCK
SET UPC=CONCAT('0',UPC) WHERE LEN(UPC)=11;

UPDATE STOCK
SET STOCK.UPC=MASTER_UPC.UPC
FROM MASTER_UPC
WHERE LEFT(CONCAT('0',STOCK.UPC),12)=MASTER_UPC.UPC;