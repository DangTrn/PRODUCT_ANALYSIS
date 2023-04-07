USE NIKE;

DECLARE @LD DATE = (SELECT MAX(CREATED_DATE) FROM SALES_DATA);
DECLARE @FD DATE = DATEADD(YEAR,-2,@LD);
WITH
	--Group allocation to get On store date
	ALC AS
		(SELECT 
			SHIPMENT SM, SKU, SIZE,
			MIN([Requested Delivery Date ]) OSD
		FROM STORE_SHIPIN, MASTER_UPC 
		WHERE [Product Code]=UPC
		GROUP BY SIZE, SKU, SHIPMENT),

	--Add season, OSD and sea_index into new_shipment
	NSM AS
		(SELECT	
			SHIPMENT, [Prod Cd], [Bill Qty], OSD,
			LEFT([Cust PO Nbr],4) AS SEA,
			CASE
				WHEN LEFT([Cust PO Nbr],2)='SP' THEN CAST(SUBSTRING([Cust PO Nbr],3,2) AS INT)*100+1
				WHEN LEFT([Cust PO Nbr],2)='SU' THEN CAST(SUBSTRING([Cust PO Nbr],3,2) AS INT)*100+2
				WHEN LEFT([Cust PO Nbr],2)='FA' THEN CAST(SUBSTRING([Cust PO Nbr],3,2) AS INT)*100+3
				ELSE CAST(SUBSTRING([Cust PO Nbr],3,2) AS INT)*100+4
			END AS SEA_INDEX
		FROM NEW_SHIPMENT LEFT JOIN ALC 
		ON [Prod Cd]=SKU AND [Sz Desc]=SIZE AND NEW_SHIPMENT.SHIPMENT=ALC.SM),

	--Choose the last 8 seasons
	LIST_SEASON AS
		(SELECT DISTINCT TOP 8 SEA_INDEX, SEA FROM NSM ORDER BY SEA_INDEX DESC),

	--define which season is the last season of each SKU
	LAST_SEASON AS
		(SELECT 
			[Prod Cd], 
			case
				WHEN MAX(SEA_INDEX) % 100 = 1 THEN CONCAT('SP',ROUND(MAX(SEA_INDEX)/100,0))
				WHEN MAX(SEA_INDEX) % 100 = 2 THEN CONCAT('SU',ROUND(MAX(SEA_INDEX)/100,0))
				WHEN MAX(SEA_INDEX) % 100 = 3 THEN CONCAT('FA',ROUND(MAX(SEA_INDEX)/100,0))
				ELSE CONCAT('HO',ROUND(MAX(SEA_INDEX)/100,0))
			END AS	LAST_SEA
		FROM NSM
		GROUP BY [Prod Cd]),

	SHIPIN AS
		(SELECT 
			NSM.[Prod Cd], NSM.SEA,
			MIN(OSD) FIRST_DATE,
			SUM([Bill Qty]) SHIPIN_QTY
		FROM NSM, LAST_SEASON
		WHERE 
			NSM.SEA IN (SELECT SEA FROM LIST_SEASON) AND 
			NSM.[Prod Cd]=LAST_SEASON.[Prod Cd] AND 
			NSM.SEA = LAST_SEASON.LAST_SEA
		GROUP BY NSM.SEA, NSM.[Prod Cd]),

	
	--select sales data
	SALES AS
		(SELECT 
			STYLE SKU, SUM(QTY) SOLD_QTY, 
			CAST(MIN(CREATED_DATE) AS DATE) FIRST_SOLD_DATE, 
			CAST(MAX(CREATED_DATE) AS DATE) LAST_SOLD_DATE
		FROM SALES_DATA, SHIPIN
		WHERE 
			CREATED_DATE BETWEEN @FD AND @LD AND 
			VEND_CODE='NIKE' AND
			STYLE=[Prod Cd] AND CREATED_DATE>= FIRST_DATE
		GROUP BY STYLE),

	--STOCK
	INVENT AS
		(SELECT DESCRIPTION1 SKU, SUM(ASN_PENDING+CLOSING) CLOSING
		FROM STOCK
		GROUP BY DESCRIPTION1)

SELECT 
	M.SKU, SHIPIN.SEA, 
	ISNULL(FIRST_DATE, FIRST_SOLD_DATE) FIRST_DATE, 
	CASE WHEN CLOSING >0 THEN @LD ELSE LAST_SOLD_DATE END AS LAST_DATE,
	DBO.MAXX(ISNULL(SOLD_QTY,0)+ISNULL(CLOSING,0) - SHIPIN_QTY,0) [BEGIN], 
	SHIPIN_QTY,
	DBO.MAXX(SHIPIN_QTY-(ISNULL(SOLD_QTY,0)+ISNULL(CLOSING,0)),0) SHIPOUT_QTY,
	ISNULL(SOLD_QTY,0) SOLD_QTY, 
	ISNULL(CLOSING,0) CLOSING,
	ISNULL(SOLD_QTY,0)/(ISNULL(SOLD_QTY,0)+ISNULL(CLOSING,0)) SELL_THROUGH,
	(DATEDIFF(
		DAY,
		ISNULL(FIRST_DATE, FIRST_SOLD_DATE),
		CASE WHEN CLOSING >0 THEN @LD ELSE LAST_SOLD_DATE END)+1)/7 WOS	
FROM 
	MASTER_FILE M
	INNER JOIN SHIPIN ON M.SKU = SHIPIN.[Prod Cd]
	LEFT JOIN SALES ON M.SKU = SALES.SKU
	LEFT JOIN INVENT ON M.SKU = INVENT.SKU
WHERE VEND='NIKE' AND ISNULL(SOLD_QTY,0)+ISNULL(CLOSING,0)>0
ORDER BY WOS DESC