use nike;

declare @ld date = (select max(created_date) from SALES_DATA);

WITH 
	SUB_SHIPIN AS
		(SELECT
			[Prod Cd],
			MIN(shipment) FIRST_SM, -- find the first shipment
			LEFT([Cust PO Nbr],4) SEASON, -- of each season
			SUM([Bill Qty]) SHIPIN_QTY, -- total qty shipin of each season
			DENSE_RANK() OVER 
				(ORDER BY CAST(SUBSTRING([Cust PO Nbr],3,2) AS INT)*100 + 
						CHARINDEX(LEFT([Cust PO Nbr],2),'SPSUFAHO') DESC) SEA_RANK1, --ranking season total to find the last 8 seasons
			DENSE_RANK() OVER 
				(PARTITION BY [Prod Cd] 
				ORDER BY CAST(SUBSTRING([Cust PO Nbr],3,2) AS INT)*100 + 
						CHARINDEX(LEFT([Cust PO Nbr],2),'SPSUFAHO') DESC) SEA_RANK2 -- ranking season of each SKU to find the last season of its
		FROM NEW_SHIPMENT
		GROUP BY 
			[Prod Cd],
			LEFT([Cust PO Nbr],4),
			CAST(SUBSTRING([Cust PO Nbr],3,2) AS INT)*100 + 
			CHARINDEX(LEFT([Cust PO Nbr],2),'SPSUFAHO')),

	FNL_SHIPIN AS
		(SELECT [Prod Cd], SEASON, FIRST_SM, SHIPIN_QTY
		FROM SUB_SHIPIN
		WHERE SEA_RANK1 <= 8 AND SEA_RANK2 = 1),

	-- Get first date
	onstore as
		(select SKU, SHIPMENT, min([Requested Delivery Date ]) OSD
		from STORE_SHIPIN, MASTER_UPC
		where [Product Code]=upc
		group by sku, SHIPMENT),

	--Get sales data
	sales as
	   	(SELECT 
			[Prod Cd],
			CAST(MIN(CREATED_DATE) AS DATE) FSD,
			CAST(MAX(CREATED_DATE) AS DATE) LSD,
			SUM(SALES_DATA.QTY) SOLD_QTY,
			sum(EXT_AMT_TOTAL) EXT_AMT,
			SUM(ORIG_AMT_TOTAL) ORG_AMT,
			1- sum(EXT_AMT_TOTAL)/SUM(ORIG_AMT_TOTAL) DISC,
			CASE 
				WHEN DATEDIFF(WEEK, OSD, @LD) >26 THEN
					SUM(CASE WHEN CREATED_DATE < DATEADD(WEEK, 26, OSD) THEN QTY END)
				ELSE SUM(SALES_DATA.QTY)/DATEDIFF(WEEK, OSD, @LD) * 26
			END AS [6M_SOLD_QTY]
		FROM 
			FNL_SHIPIN
			INNER join onstore on [Prod Cd] = SKU and FNL_SHIPIN.FIRST_SM = onstore.SHIPMENT
			inner JOIN SALES_DATA ON FNL_SHIPIN.[Prod Cd] = SALES_DATA.STYLE AND CREATED_DATE >= OSD
		GROUP BY [Prod Cd], OSD),
	
	-- Get stock data
	inventory as
		(SELECT 
			A.SKU, 
			SUM(QTY) STOCK_QTY,
			TTL_SZ_COUNT,
			SUM(SZ_COUNT*1.0/TTL_SZ_COUNT*QTY)/SUM(A.QTY) SZ_ADPTV
		FROM
			(SELECT 
				DESCRIPTION1 SKU, STORE_CODE,
				SUM(ASN_PENDING+CLOSING) QTY,
				COUNT(DISTINCT SIZ) SZ_COUNT
			FROM STOCK
			GROUP BY DESCRIPTION1, STORE_CODE
			HAVING SUM(ASN_PENDING+CLOSING)>0) A
			INNER JOIN
			(select DESCRIPTION1 SKU, COUNT(DISTINCT SIZ) TTL_SZ_COUNT
			from stock WHERE ASN_PENDING+CLOSING>0
			GROUP BY DESCRIPTION1) B
			ON A.SKU = B.SKU
		GROUP BY A.SKU, TTL_SZ_COUNT)

select 
	MASTER_FILE.SKU, DIV, GENDER, CAT, AGE, FRANCHISE, [COLLECTION], SILHOUETE, [DES], SRP, SCHEME, -- from MASTER_FILE
	FNL_SHIPIN.SEASON, FIRST_SM, 
	OSD, CASE WHEN STOCK_QTY IS NULL THEN LSD ELSE @LD END AS LAST_DATE,
	DATEDIFF(WEEK, OSD, CASE WHEN STOCK_QTY IS NULL THEN LSD ELSE @LD END) WOS,
	dbo.Maxx(isnull(SOLD_QTY,0) + ISNULL(STOCK_QTY,0)- SHIPIN_QTY,0) [BEGIN],
	SHIPIN_QTY,
	dbo.Maxx(SHIPIN_QTY - isnull(SOLD_QTY,0) - ISNULL(STOCK_QTY,0),0) SHIPOUT_QTY,
	isnull(SOLD_QTY,0) SOLD_QTY,
	ISNULL(STOCK_QTY,0) CLOSING,
	isnull(SOLD_QTY,0)/(isnull(SOLD_QTY,0) + ISNULL(STOCK_QTY,0)) SELL_THRU,
	[6M_SOLD_QTY],
	case 
		when ISNULL([6M_SOLD_QTY],0) < isnull(SOLD_QTY,0) + ISNULL(STOCK_QTY,0) then ISNULL([6M_SOLD_QTY],0)
		else isnull(SOLD_QTY,0) + ISNULL(STOCK_QTY,0)
	end as [6M_SOLD_QTY],
	case 
		when ISNULL([6M_SOLD_QTY],0) > (isnull(SOLD_QTY,0) + ISNULL(STOCK_QTY,0)) then 1
		else ISNULL([6M_SOLD_QTY],0) / (isnull(SOLD_QTY,0) + ISNULL(STOCK_QTY,0))
	end as [6M_ST],
	EXT_AMT, ORG_AMT, DISC, -- from sales
	isnull(TTL_SZ_COUNT,0) TTL_SZ_COUNT, SZ_ADPTV -- From inventory
from 
	FNL_SHIPIN
	LEFT JOIN onstore ON FNL_SHIPIN.[Prod Cd] = SKU and FIRST_SM = SHIPMENT
	LEFT JOIN SALES ON FNL_SHIPIN.[Prod Cd] = SALES.[Prod Cd]
	LEFT JOIN inventory ON FNL_SHIPIN.[Prod Cd] = inventory.SKU
	LEFT JOIN MASTER_FILE ON FNL_SHIPIN.[Prod Cd] = MASTER_FILE.SKU
WHERE isnull(SOLD_QTY,0)+ISNULL(STOCK_QTY,0) > 0;
