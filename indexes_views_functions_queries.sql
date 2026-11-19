USE [E-commerce];


/* ============================================================
   1) INDEXES  (on foreign keys + columns used in WHERE / GROUP BY)
   ============================================================ */
DROP INDEX IF EXISTS IX_Orders_CustomerID   ON Orders;
DROP INDEX IF EXISTS IX_Orders_OrderDate    ON Orders;
DROP INDEX IF EXISTS IX_OrderItem_ProductID ON OrderItem;
DROP INDEX IF EXISTS IX_Product_CategoryID  ON Product;
DROP INDEX IF EXISTS IX_Product_SupplierID  ON Product;
DROP INDEX IF EXISTS IX_Payment_OrderID     ON Payment;
DROP INDEX IF EXISTS IX_Review_CustomerID   ON Review;
DROP INDEX IF EXISTS IX_Address_CustomerID  ON Address;
DROP INDEX IF EXISTS IX_Category_Parent     ON Category;
GO

-- Covering indexes (INCLUDE) so common queries don't need to touch the table
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID   ON Orders(CustomerID)  INCLUDE (OrderDate, Status, TotalAmount);
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate    ON Orders(OrderDate)   INCLUDE (Status, TotalAmount);
CREATE NONCLUSTERED INDEX IX_OrderItem_ProductID ON OrderItem(ProductID) INCLUDE (Qty, UnitPrice);
CREATE NONCLUSTERED INDEX IX_Product_CategoryID  ON Product(CategoryID);
CREATE NONCLUSTERED INDEX IX_Product_SupplierID  ON Product(SupplierID);
CREATE NONCLUSTERED INDEX IX_Payment_OrderID     ON Payment(OrderID)    INCLUDE (Method, Amount, Status);
CREATE NONCLUSTERED INDEX IX_Review_CustomerID   ON Review(CustomerID);
CREATE NONCLUSTERED INDEX IX_Address_CustomerID  ON Address(CustomerID);
CREATE NONCLUSTERED INDEX IX_Category_Parent     ON Category(ParentCategoryID);
GO

/* ============================================================
   2) VIEWS
   ============================================================ */

-- Flat view: one row per order line with customer, city, product, category
CREATE OR ALTER VIEW vw_OrderDetails AS
SELECT o.OrderID, o.OrderDate, o.Status,
       c.CustomerID, c.FirstName + ' ' + c.LastName AS CustomerName,
       a.City,
       p.ProductID, p.Name AS ProductName, cat.Name AS CategoryName,
       oi.Qty, oi.UnitPrice, oi.Qty * oi.UnitPrice AS LineTotal
FROM Orders o
JOIN Customer  c   ON c.CustomerID  = o.CustomerID
JOIN Address   a   ON a.AddressID   = o.AddressID
JOIN OrderItem oi  ON oi.OrderID    = o.OrderID
JOIN Product   p   ON p.ProductID   = oi.ProductID
JOIN Category  cat ON cat.CategoryID = p.CategoryID;
GO

-- Sales per product (cancelled orders excluded)
CREATE OR ALTER VIEW vw_ProductSales AS
SELECT ProductID, ProductName, CategoryName,
       SUM(Qty)       AS UnitsSold,
       SUM(LineTotal) AS Revenue
FROM vw_OrderDetails
WHERE Status <> 'Cancelled'
GROUP BY ProductID, ProductName, CategoryName;
GO

-- One row per customer, including customers with no orders
CREATE OR ALTER VIEW vw_CustomerSummary AS
SELECT c.CustomerID,
       c.FirstName + ' ' + c.LastName AS CustomerName,
       c.Email,
       COUNT(o.OrderID)               AS OrdersCount,
       ISNULL(SUM(o.TotalAmount), 0)  AS TotalSpent,
       MAX(o.OrderDate)               AS LastOrderDate
FROM Customer c
LEFT JOIN Orders o ON o.CustomerID = c.CustomerID AND o.Status <> 'Cancelled'
GROUP BY c.CustomerID, c.FirstName, c.LastName, c.Email;
GO

-- Average rating and number of reviews per product
CREATE OR ALTER VIEW vw_ProductRatings AS
SELECT p.ProductID, p.Name AS ProductName,
       COUNT(r.ReviewID) AS ReviewsCount,
       CAST(AVG(CAST(r.Rating AS DECIMAL(4,2))) AS DECIMAL(3,2)) AS AvgRating
FROM Product p
LEFT JOIN Review r ON r.ProductID = p.ProductID
GROUP BY p.ProductID, p.Name;
GO

-- Products that need restocking
CREATE OR ALTER VIEW vw_LowStock AS
SELECT p.ProductID, p.Name AS ProductName, p.StockQty, s.Name AS SupplierName, s.Phone AS SupplierPhone
FROM Product p
JOIN Supplier s ON s.SupplierID = p.SupplierID
WHERE p.StockQty < 60;
GO

/* ============================================================
   3) FUNCTIONS
   ============================================================ */

-- Scalar function: loyalty discount based on number of successful orders
CREATE OR ALTER FUNCTION dbo.fn_GetCustomerDiscount (@CustomerID INT)
RETURNS DECIMAL(4,2)
AS
BEGIN
    DECLARE @cnt INT, @discount DECIMAL(4,2);

    SELECT @cnt = COUNT(*)
    FROM Orders
    WHERE CustomerID = @CustomerID
      AND Status IN ('Paid', 'Shipped', 'Delivered');

    IF @cnt >= 5      SET @discount = 0.10;   -- 10%
    ELSE IF @cnt >= 3 SET @discount = 0.05;   -- 5%
    ELSE              SET @discount = 0.00;

    RETURN @discount;
END;
GO

-- Inline table-valued function: all orders of one customer with payment info
CREATE OR ALTER FUNCTION dbo.fn_GetCustomerOrders (@CustomerID INT)
RETURNS TABLE
AS
RETURN
(
    SELECT o.OrderID, o.OrderDate, o.Status, o.TotalAmount,
           p.Method, p.Status AS PaymentStatus
    FROM Orders o
    LEFT JOIN Payment p ON p.OrderID = o.OrderID
    WHERE o.CustomerID = @CustomerID
);
GO

/* ============================================================
   4) REPORTING QUERIES  (run each one separately and read the output)
   ============================================================ */

-- Q1. Top 5 products by revenue
SELECT TOP 5 ProductName, CategoryName, UnitsSold, Revenue
FROM vw_ProductSales
ORDER BY Revenue DESC;

-- Q2. Top 10 customers: RANK vs DENSE_RANK vs NTILE (quartiles)
SELECT TOP 10 CustomerID, CustomerName, TotalSpent,
       RANK()       OVER (ORDER BY TotalSpent DESC) AS SpendRank,
       DENSE_RANK() OVER (ORDER BY TotalSpent DESC) AS DenseSpendRank,
       NTILE(4)     OVER (ORDER BY TotalSpent DESC) AS Quartile
FROM vw_CustomerSummary
ORDER BY TotalSpent DESC;

-- Q3. Best-selling product in each category (ROW_NUMBER + PARTITION BY)
SELECT CategoryName, ProductName, Revenue
FROM (
    SELECT CategoryName, ProductName, Revenue,
           ROW_NUMBER() OVER (PARTITION BY CategoryName ORDER BY Revenue DESC) AS rn
    FROM vw_ProductSales
) x
WHERE rn = 1
ORDER BY Revenue DESC;

-- Q4. Monthly revenue + running total + month-over-month growth (LAG)
;WITH M AS (
    SELECT DATEFROMPARTS(YEAR(OrderDate), MONTH(OrderDate), 1) AS MonthStart,
           COUNT(*)         AS OrdersCount,
           SUM(TotalAmount) AS Revenue
    FROM Orders
    WHERE Status <> 'Cancelled'
    GROUP BY DATEFROMPARTS(YEAR(OrderDate), MONTH(OrderDate), 1)
)
SELECT MonthStart, OrdersCount, Revenue,
       SUM(Revenue) OVER (ORDER BY MonthStart ROWS UNBOUNDED PRECEDING) AS RunningTotal,
       LAG(Revenue) OVER (ORDER BY MonthStart)                          AS PrevMonthRevenue,
       CAST((Revenue - LAG(Revenue) OVER (ORDER BY MonthStart)) * 100.0
            / NULLIF(LAG(Revenue) OVER (ORDER BY MonthStart), 0) AS DECIMAL(7,2)) AS GrowthPct
FROM M
ORDER BY MonthStart;

-- Q5. PIVOT: monthly revenue per main category (one column per category)
SELECT MonthLabel, [Electronics], [Fashion], [Home & Kitchen], [Books], [Sports]
FROM (
    SELECT FORMAT(o.OrderDate, 'yyyy-MM') AS MonthLabel,
           pc.Name                        AS ParentCategory,
           oi.Qty * oi.UnitPrice          AS LineTotal
    FROM Orders o
    JOIN OrderItem oi ON oi.OrderID    = o.OrderID
    JOIN Product   p  ON p.ProductID   = oi.ProductID
    JOIN Category  c  ON c.CategoryID  = p.CategoryID
    JOIN Category  pc ON pc.CategoryID = c.ParentCategoryID
    WHERE o.Status <> 'Cancelled'
) src
PIVOT (SUM(LineTotal) FOR ParentCategory IN ([Electronics], [Fashion], [Home & Kitchen], [Books], [Sports])) pvt
ORDER BY MonthLabel;

-- Q6. Payment methods: count, total and share of completed payments
SELECT Method,
       COUNT(*)    AS Payments,
       SUM(Amount) AS TotalAmount,
       CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS SharePct
FROM Payment
WHERE Status = 'Completed'
GROUP BY Method
ORDER BY Payments DESC;

-- Q7. Orders by status and city (which cities have the most cancellations?)
SELECT City,
       COUNT(DISTINCT OrderID) AS Orders,
       COUNT(DISTINCT CASE WHEN Status = 'Cancelled' THEN OrderID END) AS Cancelled
FROM vw_OrderDetails
GROUP BY City
ORDER BY Cancelled DESC;

-- Q8. Highly rated products (avg >= 4 with at least 3 reviews)
SELECT ProductName, ReviewsCount, AvgRating
FROM vw_ProductRatings
WHERE AvgRating >= 4 AND ReviewsCount >= 3
ORDER BY AvgRating DESC, ReviewsCount DESC;

-- Q9. Customers who never ordered, and products that never sold (may return 0 rows)
SELECT CustomerID, CustomerName, Email FROM vw_CustomerSummary WHERE OrdersCount = 0;

SELECT p.ProductID, p.Name
FROM Product p
LEFT JOIN OrderItem oi ON oi.ProductID = p.ProductID
WHERE oi.OrderItemID IS NULL;

-- Q10. Customers with a cart but no orders (abandoned carts to target with an offer)
SELECT c.CustomerID, c.FirstName + ' ' + c.LastName AS CustomerName,
       SUM(ci.Qty * p.Price) AS CartValue
FROM Cart ca
JOIN Customer c  ON c.CustomerID = ca.CustomerID
JOIN CartItem ci ON ci.CartID    = ca.CartID
JOIN Product  p  ON p.ProductID  = ci.ProductID
WHERE NOT EXISTS (SELECT 1 FROM Orders o WHERE o.CustomerID = c.CustomerID)
GROUP BY c.CustomerID, c.FirstName, c.LastName;

-- Q11. Using the functions
SELECT TOP 15 CustomerID, CustomerName, OrdersCount,
       dbo.fn_GetCustomerDiscount(CustomerID) AS DiscountRate
FROM vw_CustomerSummary
ORDER BY OrdersCount DESC;

SELECT * FROM dbo.fn_GetCustomerOrders(1) ORDER BY OrderDate DESC;

/* ============================================================
   5) MERGE DEMO  (upsert from a staging table)
   - Existing product with a different price -> UPDATE
   - Product not found                       -> INSERT
   ============================================================ */
CREATE TABLE #Staging (
    Name NVARCHAR(150), Price DECIMAL(10,2), StockQty INT, CategoryID INT, SupplierID INT
);

INSERT INTO #Staging
SELECT 'Samsung Galaxy A55', 13900.00, 80,
       (SELECT CategoryID FROM Category WHERE Name = 'Mobile Phones'),
       (SELECT SupplierID FROM Supplier WHERE Name = 'Delta Electronics')
UNION ALL
SELECT 'Logitech MX Master 3', 3400.00, 60,
       (SELECT CategoryID FROM Category WHERE Name = 'Electronics'),
       (SELECT SupplierID FROM Supplier WHERE Name = 'Cairo Tech Distribution');

MERGE Product AS tgt
USING #Staging AS src
   ON tgt.Name = src.Name
WHEN MATCHED AND tgt.Price <> src.Price THEN
    UPDATE SET tgt.Price = src.Price
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Name, Price, StockQty, CategoryID, SupplierID)
    VALUES (src.Name, src.Price, src.StockQty, src.CategoryID, src.SupplierID)
OUTPUT $action AS MergeAction, inserted.ProductID, inserted.Name, inserted.Price;

DROP TABLE #Staging;
GO
