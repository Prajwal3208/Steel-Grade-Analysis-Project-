CREATE DATABASE steel_project;

SHOW DATABASES;

use steel_project;

SHOW TABLES;

ALTER TABLE grade_master 
ADD PRIMARY KEY (GRADE_ID);

ALTER TABLE heat_master 
ADD PRIMARY KEY (HEAT_ID);

ALTER TABLE raw_material_log 
ADD PRIMARY KEY (LOG_ID);

ALTER TABLE process_metrics 
ADD PRIMARY KEY (METRIC_ID);

ALTER TABLE shift_performance 
ADD PRIMARY KEY (SHIFT_ID);

ALTER TABLE quality_analysis 
ADD PRIMARY KEY (QA_ID);

ALTER TABLE heat_master
ADD INDEX idx_heatno (HEATNO);

ALTER TABLE profit_margin 
ADD PRIMARY KEY (GRADE_ID);

ALTER TABLE heat_master
ADD CONSTRAINT fk_heat_grade
FOREIGN KEY (GRADE_ID) REFERENCES grade_master(GRADE_ID);

ALTER TABLE raw_material_log
ADD CONSTRAINT fk_raw_heat
FOREIGN KEY (HEATNO) REFERENCES heat_master(HEATNO);

ALTER TABLE process_metrics
ADD CONSTRAINT fk_process_heat
FOREIGN KEY (HEATNO) REFERENCES heat_master(HEATNO);

ALTER TABLE shift_performance
ADD CONSTRAINT fk_shift_heat
FOREIGN KEY (HEATNO) REFERENCES heat_master(HEATNO);

ALTER TABLE quality_analysis
ADD CONSTRAINT fk_quality_heat
FOREIGN KEY (HEATNO) REFERENCES heat_master(HEATNO);

ALTER TABLE profit_margin
ADD CONSTRAINT fk_profit_grade
FOREIGN KEY (GRADE_ID) REFERENCES grade_master(GRADE_ID);

ALTER TABLE profit_margin
ADD INDEX idx_profit_grade (GRADE_ID);

--  ---------------------------------------------------------------------------------
-- 1.calculate total production quantity (MT) for each steel grade.
SELECT 
    gm.GRADE,
    ROUND(SUM(hm.`Production (MT)`), 2) AS Total_Production_MT
FROM heat_master hm
JOIN grade_master gm 
    ON hm.GRADE_ID = gm.GRADE_ID
GROUP BY gm.GRADE
ORDER BY Total_Production_MT DESC;


-- 2.Find the top 5 most produced steel grades by total quantity.
SELECT 
    gm.GRADE,
    ROUND(SUM(hm.`Production (MT)`), 2) AS Total_Production_MT
FROM heat_master hm
JOIN grade_master gm 
    ON hm.GRADE_ID = gm.GRADE_ID
GROUP BY gm.GRADE
ORDER BY Total_Production_MT DESC
LIMIT 5;

-- 3.Compute the average energy consumption per ton for each steel grade
SELECT 
    gm.GRADE,
    ROUND(AVG(pm.`KWH_PER_TON (Energy Consumption Per Ton)`), 2) AS Avg_Energy_per_Ton
FROM process_metrics pm
JOIN heat_master hm 
    ON pm.HEATNO = hm.HEATNO
JOIN grade_master gm 
    ON hm.GRADE_ID = gm.GRADE_ID
WHERE pm.`KWH_PER_TON (Energy Consumption Per Ton)` > 0
GROUP BY gm.GRADE
ORDER BY Avg_Energy_per_Ton ASC;

-- 4:Join grade-wise data with profit margin table to calculate total revenue contribution.
SELECT 
    g.GRADE,
    g.SECTION as product_category,
    COUNT(*) as heat_count,
    SUM(h.`Production (MT)`) as total_production,
    pm.PROFIT_PER_MT,
    pm.REVENUE_PER_MT,
    SUM(h.`Production (MT)`) * pm.PROFIT_PER_MT as total_profit,
    ROUND((pm.PROFIT_PER_MT / pm.REVENUE_PER_MT) * 100, 2) as profit_margin_percentage
FROM heat_master h
JOIN grade_master g ON h.GRADE_ID = g.GRADE_ID
JOIN profit_margin pm ON g.GRADE_ID = pm.GRADE_ID
WHERE h.`Production (MT)` > 0
GROUP BY g.GRADE, g.SECTION, pm.PROFIT_PER_MT, pm.REVENUE_PER_MT
ORDER BY total_profit DESC
LIMIT 50;


-- 5.Identify grades where production quantity increased but profit margin decreased over time.

WITH monthly_trends AS (
    SELECT 
        g.GRADE,
        YEAR(h.DATETIME) as year,
        MONTH(h.DATETIME) as month,
        SUM(h.`Production (MT)`) as monthly_production,
        AVG(pm.PROFIT_PER_MT) as profit_margin
    FROM heat_master h
    JOIN grade_master g ON h.GRADE_ID = g.GRADE_ID
    JOIN profit_margin pm ON g.GRADE_ID = pm.GRADE_ID
    GROUP BY g.GRADE, YEAR(h.DATETIME), MONTH(h.DATETIME)
),
trend_comparison AS (
    SELECT 
        GRADE,
        year,
        month,
        monthly_production,
        profit_margin,
        LAG(monthly_production) OVER (PARTITION BY GRADE ORDER BY year, month) as prev_production,
        LAG(profit_margin) OVER (PARTITION BY GRADE ORDER BY year, month) as prev_profit_margin
    FROM monthly_trends
)
SELECT 
    GRADE,
    year,
    month,
    monthly_production,
    profit_margin,
    (monthly_production - prev_production) as production_change,
    (profit_margin - prev_profit_margin) as profit_margin_change,
    CASE 
        WHEN (monthly_production - prev_production) > 0 AND (profit_margin - prev_profit_margin) < 0 THEN 'WARNING: Volume up but margin down'
        ELSE 'Stable'
    END as trend_status
FROM trend_comparison
WHERE prev_production IS NOT NULL
  AND monthly_production > prev_production
  AND profit_margin < prev_profit_margin
ORDER BY production_change DESC;

-- 6: Find grades with the highest scrap or rejection percentage
SELECT 
    hm.GRADE,
    ROUND(SUM(rm.`SCRAP_QTY (MT)`), 2) AS Total_Scrap_MT,
    ROUND(SUM(hm.`Production (MT)`), 2) AS Total_Production_MT,
    ROUND((SUM(rm.`SCRAP_QTY (MT)`) / NULLIF(SUM(hm.`Production (MT)`), 0)) * 100, 2) AS Scrap_Percentage
FROM heat_master hm
JOIN raw_material_log rm ON hm.HEATNO = rm.HEATNO
GROUP BY hm.GRADE
ORDER BY Scrap_Percentage DESC
LIMIT 10;

-- Query 7 without tap temperature (focus on yield analysis)
SELECT
    hm.GRADE,
    ROUND(AVG((hm.`Production (MT)` / NULLIF(rm.`Total Charge`, 0)) * 100), 2) AS Avg_Yield_Percentage,
    COUNT(*) as heat_count,
    SUM(hm.`Production (MT)`) as total_production,
    SUM(rm.`Total Charge`) as total_input
FROM heat_master hm
JOIN raw_material_log rm ON hm.HEATNO = rm.HEATNO
WHERE rm.`Total Charge` > 0 
  AND hm.`Production (MT)` > 0
GROUP BY hm.GRADE
HAVING heat_count >= 3
ORDER BY Avg_Yield_Percentage DESC;	

-- SQL-008: Calculate grade-wise resource consumption ratios (Scrap, Coke, DRI, Lime)
SELECT
    hm.GRADE,
    ROUND(SUM(rm.`SCRAP_QTY (MT)`) / NULLIF(SUM(hm.`Production (MT)`), 0), 4) AS Scrap_Ratio,
    ROUND(SUM(rm.`COKE_REQ`) / NULLIF(SUM(hm.`Production (MT)`), 0), 4) AS Coke_Ratio,
    ROUND(SUM(rm.`TOT_DRI_QTY`) / NULLIF(SUM(hm.`Production (MT)`), 0), 4) AS DRI_Ratio,
    ROUND(SUM(rm.`TOT_LIME_QTY`) / NULLIF(SUM(hm.`Production (MT)`), 0), 4) AS Lime_Ratio
FROM heat_master hm
JOIN raw_material_log rm 
    ON hm.HEATNO = rm.HEATNO
GROUP BY hm.GRADE
ORDER BY hm.GRADE;

-- Query 9: Create monthly production and profitability summary view

CREATE VIEW monthly_grade_summary AS
SELECT 
    g.GRADE,
    g.SECTION as product_category,
    YEAR(h.DATETIME) as year,
    MONTH(h.DATETIME) as month,
    COUNT(*) as heat_count,
    SUM(h.`Production (MT)`) as total_production,
    
    -- Financial metrics
    pm.PROFIT_PER_MT,
    pm.REVENUE_PER_MT,
    SUM(h.`Production (MT)`) * pm.PROFIT_PER_MT as total_profit,
    SUM(h.`Production (MT)`) * pm.REVENUE_PER_MT as total_revenue,
    
    -- Efficiency metrics
    AVG(p.`KWH_PER_TON (Energy Consumption Per Ton)`) as avg_energy_per_ton,
    AVG((h.`Production (MT)` / r.`Total Charge`) * 100) as avg_yield_percentage,
    AVG(s.`TT_TIME (Total Cycle Time Including Breakdown)`) as avg_total_cycle_time

FROM heat_master h
JOIN grade_master g ON h.GRADE_ID = g.GRADE_ID
JOIN profit_margin pm ON g.GRADE_ID = pm.GRADE_ID
LEFT JOIN process_metrics p ON h.HEATNO = p.HEATNO
LEFT JOIN raw_material_log r ON h.HEATNO = r.HEATNO
LEFT JOIN shift_performance s ON h.HEATNO = s.HEATNO

WHERE r.`Total Charge` > 0 AND h.`Production (MT)` > 0

GROUP BY g.GRADE, g.SECTION, YEAR(h.DATETIME), MONTH(h.DATETIME), pm.PROFIT_PER_MT, pm.REVENUE_PER_MT;

-- Query 10: Rank grades by profitability within each product category
WITH grade_profitability AS (
    SELECT 
        g.GRADE,
        g.SECTION as product_category,
        SUM(h.`Production (MT)`) as total_production,
        pm.PROFIT_PER_MT,
        pm.REVENUE_PER_MT,
        SUM(h.`Production (MT)`) * pm.PROFIT_PER_MT as total_profit,
        SUM(h.`Production (MT)`) * pm.REVENUE_PER_MT as total_revenue
    FROM heat_master h
    JOIN grade_master g ON h.GRADE_ID = g.GRADE_ID
    JOIN profit_margin pm ON g.GRADE_ID = pm.GRADE_ID
    WHERE h.`Production (MT)` > 0
    GROUP BY g.GRADE, g.SECTION, pm.PROFIT_PER_MT, pm.REVENUE_PER_MT
)
SELECT 
    GRADE,
    product_category,
    total_production,
    PROFIT_PER_MT,
    total_profit,
    total_revenue,
    RANK() OVER (PARTITION BY product_category ORDER BY total_profit DESC) as profitability_rank,
    ROUND((total_profit / total_revenue) * 100, 2) as profit_margin_percentage
FROM grade_profitability
ORDER BY product_category, profitability_rank;

-- 11: Identify top and bottom 3 grades per product category based on profitability

WITH grade_profitability AS (
    SELECT 
        g.GRADE,
        g.SECTION AS product_category,
        SUM(h.`Production (MT)`) AS total_production,
        pm.PROFIT_PER_MT,
        pm.REVENUE_PER_MT,
        SUM(h.`Production (MT)`) * pm.PROFIT_PER_MT AS total_profit,
        SUM(h.`Production (MT)`) * pm.REVENUE_PER_MT AS total_revenue
    FROM heat_master h
    JOIN grade_master g ON h.GRADE_ID = g.GRADE_ID
    JOIN profit_margin pm ON g.GRADE_ID = pm.GRADE_ID
    WHERE h.`Production (MT)` > 0
    GROUP BY g.GRADE, g.SECTION, pm.PROFIT_PER_MT, pm.REVENUE_PER_MT
),
ranked AS (
    SELECT 
        GRADE,
        product_category,
        total_production,
        total_profit,
        total_revenue,
        ROUND((total_profit / total_revenue) * 100, 2) AS profit_margin_percentage,
        RANK() OVER (PARTITION BY product_category ORDER BY total_profit DESC) AS profit_rank,
        RANK() OVER (PARTITION BY product_category ORDER BY total_profit ASC) AS loss_rank
    FROM grade_profitability
)
SELECT 
    product_category,
    GRADE,
    total_production,
    total_profit,
    profit_margin_percentage,
    CASE 
        WHEN profit_rank <= 3 THEN 'TOP Performer'
        WHEN loss_rank <= 3 THEN 'LOW Performer'
        ELSE 'AVERAGE'
    END AS performance_status
FROM ranked
WHERE profit_rank <= 3 OR loss_rank <= 3
ORDER BY product_category, performance_status, total_profit DESC;

-- 12: Trigger to log missing composition data for new grade entries
DROP TRIGGER IF EXISTS trg_missing_composition_check;

DELIMITER $$

CREATE TRIGGER trg_missing_composition_check
AFTER INSERT ON quality_analysis
FOR EACH ROW
BEGIN
    DECLARE missing_list TEXT DEFAULT '';

    IF NEW.C IS NULL OR NEW.C = '' THEN
        SET missing_list = CONCAT(missing_list, 'C, ');
    END IF;
    IF NEW.SI IS NULL OR NEW.SI = '' THEN
        SET missing_list = CONCAT(missing_list, 'SI, ');
    END IF;
    IF NEW.MN IS NULL OR NEW.MN = '' THEN
        SET missing_list = CONCAT(missing_list, 'MN, ');
    END IF;
    IF NEW.P IS NULL OR NEW.P = '' THEN
        SET missing_list = CONCAT(missing_list, 'P, ');
    END IF;
    IF NEW.S IS NULL OR NEW.S = '' THEN
        SET missing_list = CONCAT(missing_list, 'S, ');
    END IF;

    IF missing_list <> '' THEN
        INSERT INTO composition_audit_log (GRADE_ID, GRADE, HEATNO, Missing_Fields)
        SELECT 
            hm.GRADE_ID,
            hm.GRADE,
            NEW.HEATNO,
            LEFT(missing_list, LENGTH(missing_list) - 2)
        FROM heat_master hm
        WHERE hm.HEATNO = NEW.HEATNO;
    END IF;
END$$

DELIMITER ;

SHOW TRIGGERS;
-- 13.  Compare total charge input vs. production output for each grade.
SELECT  
    gm.GRADE,  
    SUM(rml.`Total Charge`) AS total_charge_input,  
    SUM(hm.`Production (MT)`) AS total_production_output,  
    ROUND((SUM(hm.`Production (MT)`) / SUM(rml.`Total Charge`)) * 100, 2) AS yield_efficiency_percentage  
FROM heat_master hm  
JOIN raw_material_log rml ON hm.HEATNO = rml.HEATNO  
JOIN grade_master gm ON hm.GRADE_ID = gm.GRADE_ID  
WHERE rml.`Total Charge` > 0 
  AND hm.`Production (MT)` > 0  
GROUP BY gm.GRADE  
ORDER BY yield_efficiency_percentage DESC;

-- Query 14: Correlation between grade composition and energy consumption
SELECT      
    g.GRADE,
    ROUND(AVG(p.`KWH_PER_TON (Energy Consumption Per Ton)`), 2) as avg_energy_per_ton,
    COUNT(*) as sample_count

FROM heat_master h 
JOIN grade_master g ON h.GRADE_ID = g.GRADE_ID 
JOIN process_metrics p ON h.HEATNO = p.HEATNO

WHERE p.`KWH_PER_TON (Energy Consumption Per Ton)` IS NOT NULL 
  AND p.`KWH_PER_TON (Energy Consumption Per Ton)` > 0 
  AND h.`Production (MT)` > 0

GROUP BY g.GRADE 
HAVING sample_count >= 5
ORDER BY avg_energy_per_ton DESC 
LIMIT 50 ; -- Reduced limit


-- 15.Analyze month-over-month change in total production quantity per grade.
WITH monthly_production AS (
    SELECT 
        g.GRADE,
        YEAR(h.DATETIME) as year,
        MONTH(h.DATETIME) as month,
        SUM(h.`Production (MT)`) as total_production,
        COUNT(*) as heat_count
    FROM heat_master h 
    JOIN grade_master g ON h.GRADE_ID = g.GRADE_ID 
    WHERE h.`Production (MT)` > 0
        AND h.DATETIME IS NOT NULL
    GROUP BY g.GRADE, YEAR(h.DATETIME), MONTH(h.DATETIME)
    HAVING heat_count >= 3
),
production_with_lag AS (
    SELECT *,
        LAG(total_production) OVER (PARTITION BY GRADE ORDER BY year, month) as prev_month_production,
        LAG(year) OVER (PARTITION BY GRADE ORDER BY year, month) as prev_year,
        LAG(month) OVER (PARTITION BY GRADE ORDER BY year, month) as prev_month
    FROM monthly_production
)
SELECT 
    GRADE,
    year,
    month,
    total_production,
    prev_month_production,
    ROUND(
        CASE 
            WHEN prev_month_production > 0 
            THEN ((total_production - prev_month_production) / prev_month_production) * 100 
            ELSE NULL 
        END, 2
    ) as mom_change_percent,
    ROUND(total_production - prev_month_production, 2) as mom_change_absolute,
    heat_count
FROM production_with_lag
WHERE prev_month_production IS NOT NULL
ORDER BY GRADE, year DESC, month DESC;

-- 16.Calculate grade mix ratio = (Grade Output ÷ Total Output) × 100 for each month.
WITH monthly_totals AS (
    SELECT 
        YEAR(h.DATETIME) as year,
        MONTH(h.DATETIME) as month,
        SUM(h.`Production (MT)`) as total_monthly_production
    FROM heat_master h
    WHERE h.`Production (MT)` > 0
        AND h.DATETIME IS NOT NULL
    GROUP BY YEAR(h.DATETIME), MONTH(h.DATETIME)
),
grade_monthly AS (
    SELECT 
        g.GRADE,
        YEAR(h.DATETIME) as year,
        MONTH(h.DATETIME) as month,
        SUM(h.`Production (MT)`) as grade_production,
        COUNT(*) as heat_count
    FROM heat_master h 
    JOIN grade_master g ON h.GRADE_ID = g.GRADE_ID 
    WHERE h.`Production (MT)` > 0
        AND h.DATETIME IS NOT NULL
    GROUP BY g.GRADE, YEAR(h.DATETIME), MONTH(h.DATETIME)
)
SELECT 
    gm.GRADE,
    gm.year,
    gm.month,
    gm.grade_production,
    mt.total_monthly_production,
    ROUND((gm.grade_production / mt.total_monthly_production) * 100, 2) as grade_mix_percentage,
    gm.heat_count
FROM grade_monthly gm
JOIN monthly_totals mt ON gm.year = mt.year AND gm.month = mt.month
WHERE mt.total_monthly_production > 0
ORDER BY gm.year DESC, gm.month DESC, grade_mix_percentage DESC;

-- 17.Create a stored procedure to return grade-wise profitability summary by date range.
DROP PROCEDURE IF EXISTS GetGradeProfitabilitySummary;

DELIMITER //

CREATE PROCEDURE GetGradeProfitabilitySummary(
    IN start_date DATE,
    IN end_date DATE
)
BEGIN
    -- Basic production summary only
    SELECT 
        g.GRADE,
        COUNT(*) as total_heats,
        SUM(h.`Production (MT)`) as total_production,
        ROUND(AVG(h.`Production (MT)`), 2) as avg_production_per_heat
    FROM heat_master h 
    JOIN grade_master g ON h.GRADE_ID = g.GRADE_ID 
    WHERE h.DATETIME BETWEEN start_date AND end_date
        AND h.`Production (MT)` > 0
    GROUP BY g.GRADE
    HAVING total_heats >= 3
    ORDER BY total_production DESC;
END //

DELIMITER ;

-- Test with small date range
CALL GetGradeProfitabilitySummary('2023-09-01', '2023-09-10');

SHOW PROCEDURE STATUS LIKE 'GetGradeProfitabilitySummary';

CALL GetGradeProfitabilitySummary('2023-09-01', '2023-09-07');

-- 18.Identify grades that require above-average furnace time per ton.
WITH monthly_totals AS (
    SELECT 
        YEAR(h.DATETIME) as year,
        MONTH(h.DATETIME) as month,
        SUM(h.`Production (MT)`) as total_monthly_production
    FROM heat_master h
    WHERE h.`Production (MT)` > 0
        AND h.DATETIME IS NOT NULL
    GROUP BY YEAR(h.DATETIME), MONTH(h.DATETIME)
),
grade_monthly AS (
    SELECT 
        g.GRADE,
        YEAR(h.DATETIME) as year,
        MONTH(h.DATETIME) as month,
        SUM(h.`Production (MT)`) as grade_production,
        COUNT(*) as heat_count
    FROM heat_master h 
    JOIN grade_master g ON h.GRADE_ID = g.GRADE_ID 
    WHERE h.`Production (MT)` > 0
        AND h.DATETIME IS NOT NULL
    GROUP BY g.GRADE, YEAR(h.DATETIME), MONTH(h.DATETIME)
)
SELECT 
    gm.GRADE,
    gm.year,
    gm.month,
    gm.grade_production,
    mt.total_monthly_production,
    ROUND((gm.grade_production / mt.total_monthly_production) * 100, 2) as grade_mix_percentage,
    gm.heat_count
FROM grade_monthly gm
JOIN monthly_totals mt ON gm.year = mt.year AND gm.month = mt.month
WHERE mt.total_monthly_production > 0
ORDER BY gm.year DESC, gm.month DESC, grade_mix_percentage DESC
LIMIT 100;

-- 19.Compare profitability between automotive, construction, and industrial grade segments.


SELECT 
    CASE 
        WHEN g.GRADE LIKE '%AUTO%' THEN 'Automotive'
        WHEN g.GRADE LIKE '%CONST%' THEN 'Construction' 
        WHEN g.GRADE LIKE '%IND%' THEN 'Industrial'
        ELSE 'Other'
    END as segment,
    COUNT(*) as total_heats,
    ROUND(SUM(h.`Production (MT)`), 2) as total_production,
    ROUND(AVG(h.`Production (MT)`), 2) as avg_production_per_heat,
    ROUND(AVG(p.`KWH_PER_TON (Energy Consumption Per Ton)`), 2) as avg_energy_per_ton
FROM heat_master h 
JOIN grade_master g ON h.GRADE_ID = g.GRADE_ID 
LEFT JOIN process_metrics p ON h.HEATNO = p.HEATNO
WHERE h.`Production (MT)` > 0
    AND p.`KWH_PER_TON (Energy Consumption Per Ton)` > 0
GROUP BY segment
HAVING total_heats >= 5
ORDER BY total_production DESC
LIMIT 50;

-- 20.Find grades with stable performance across months (low variance in output and profit).

SELECT 
    g.GRADE,
    COUNT(*) as total_heats,
    ROUND(AVG(h.`Production (MT)`), 2) as avg_production,
    ROUND(STDDEV(h.`Production (MT)`), 2) as std_production,
    ROUND((STDDEV(h.`Production (MT)`) / AVG(h.`Production (MT)`)) * 100, 2) as production_variation_percent
FROM heat_master h 
JOIN grade_master g ON h.GRADE_ID = g.GRADE_ID 
WHERE h.`Production (MT)` > 0
GROUP BY g.GRADE
HAVING total_heats >= 10  -- More heats for stability analysis
    AND (STDDEV(h.`Production (MT)`) / AVG(h.`Production (MT)`)) * 100 < 30  -- Less than 30% variation
ORDER BY production_variation_percent ASC
LIMIT 50;