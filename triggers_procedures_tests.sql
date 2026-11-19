/* ============================================================
   E-Commerce Project | DAY 3: Audit tables, Triggers, Stored Procedures, Tests
   Run AFTER Day 1 (ecommerce_db.sql) and Day 2 (ecommerce_day2.sql).
   Needs: fn_GetCustomerDiscount and vw_OrderDetails from Day 2.
   Change the USE line if your database has a different name.
   Safe to re-run (CREATE OR ALTER / IF OBJECT_ID checks).
   ============================================================ */

USE [E-commerce];
GO

/* ============================================================
   1) AUDIT TABLES
   ============================================================ */
IF OBJECT_ID('dbo.OrderStatusLog') IS NULL
BEGIN
    CREATE TABLE OrderStatusLog (
        LogID     INT IDENTITY(1,1) CONSTRAINT PK_OrderStatusLog PRIMARY KEY,
        OrderID   INT NOT NULL CONSTRAINT FK_OrderStatusLog_Orders REFERENCES Orders(OrderID),
        OldStatus VARCHAR(20) NOT NULL,
        NewStatus VARCHAR(20) NOT NULL,
        ChangedAt DATETIME NOT NULL CONSTRAINT DF_OrderStatusLog_ChangedAt DEFAULT GETDATE(),
        ChangedBy SYSNAME  NOT NULL CONSTRAINT DF_OrderStatusLog_ChangedBy DEFAULT SUSER_SNAME()
    );
END
GO

IF OBJECT_ID('dbo.PriceHistory') IS NULL
BEGIN
    CREATE TABLE PriceHistory (
        HistoryID INT IDENTITY(1,1) CONSTRAINT PK_PriceHistory PRIMARY KEY,
        ProductID INT NOT NULL CONSTRAINT FK_PriceHistory_Product REFERENCES Product(ProductID),
        OldPrice  DECIMAL(10,2) NOT NULL,
        NewPrice  DECIMAL(10,2) NOT NULL,
        ChangedAt DATETIME NOT NULL CONSTRAINT DF_PriceHistory_ChangedAt DEFAULT GETDATE()
    );
END
GO

/* ============================================================
   2) TRIGGERS
   ============================================================ */

-- T1. AFTER INSERT on OrderItem: block overselling, then reduce stock
CREATE OR ALTER TRIGGER trg_OrderItem_ReduceStock
ON OrderItem
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- total quantity per product in this insert (an order can add several rows at once)
    IF EXISTS (
        SELECT 1
        FROM Product p
        JOIN (SELECT ProductID, SUM(Qty) AS Qty FROM inserted GROUP BY ProductID) i
          ON i.ProductID = p.ProductID
        WHERE p.StockQty < i.Qty
    )
    BEGIN
        RAISERROR('Insufficient stock for one or more products.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    UPDATE p
    SET p.StockQty = p.StockQty - i.Qty
    FROM Product p
    JOIN (SELECT ProductID, SUM(Qty) AS Qty FROM inserted GROUP BY ProductID) i
      ON i.ProductID = p.ProductID;
END;
GO

-- T2. AFTER UPDATE on Orders: validate status change, write audit log, restore stock on cancel
CREATE OR ALTER TRIGGER trg_Orders_StatusChange
ON Orders
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(Status) RETURN;

    -- Delivered and Cancelled orders are final
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON d.OrderID = i.OrderID
        WHERE d.Status IN ('Delivered', 'Cancelled') AND i.Status <> d.Status
    )
    BEGIN
        RAISERROR('Cannot change the status of a Delivered or Cancelled order.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    -- Audit log
    INSERT INTO OrderStatusLog (OrderID, OldStatus, NewStatus)
    SELECT i.OrderID, d.Status, i.Status
    FROM inserted i
    JOIN deleted d ON d.OrderID = i.OrderID
    WHERE i.Status <> d.Status;

    -- Give the stock back when an order becomes Cancelled
    UPDATE p
    SET p.StockQty = p.StockQty + x.Qty
    FROM Product p
    JOIN (
        SELECT oi.ProductID, SUM(oi.Qty) AS Qty
        FROM OrderItem oi
        JOIN inserted i ON i.OrderID = oi.OrderID
        JOIN deleted  d ON d.OrderID = i.OrderID
        WHERE i.Status = 'Cancelled' AND d.Status <> 'Cancelled'
        GROUP BY oi.ProductID
    ) x ON x.ProductID = p.ProductID;
END;
GO

-- T3. AFTER INSERT/UPDATE on Payment: a completed payment marks a pending order as Paid
CREATE OR ALTER TRIGGER trg_Payment_MarkOrderPaid
ON Payment
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE o
    SET o.Status = 'Paid'
    FROM Orders o
    JOIN inserted i ON i.OrderID = o.OrderID
    WHERE i.Status = 'Completed' AND o.Status = 'Pending';
END;
GO

-- T4. AFTER UPDATE on Product: keep a price history
CREATE OR ALTER TRIGGER trg_Product_PriceHistory
ON Product
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(Price) RETURN;

    INSERT INTO PriceHistory (ProductID, OldPrice, NewPrice)
    SELECT i.ProductID, d.Price, i.Price
    FROM inserted i
    JOIN deleted d ON d.ProductID = i.ProductID
    WHERE i.Price <> d.Price;
END;
GO

-- T5. INSTEAD OF DELETE on Customer: soft delete (keep history, just deactivate)
CREATE OR ALTER TRIGGER trg_Customer_SoftDelete
ON Customer
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE c
    SET c.IsActive = 0
    FROM Customer c
    JOIN deleted d ON d.CustomerID = c.CustomerID;
END;
GO

/* ============================================================
   3) STORED PROCEDURES
   ============================================================ */

-- P1. Register a customer together with a default address
CREATE OR ALTER PROCEDURE usp_AddCustomer
    @FirstName  NVARCHAR(50),
    @LastName   NVARCHAR(50),
    @Email      NVARCHAR(100),
    @Phone      VARCHAR(15),
    @City       NVARCHAR(50),
    @Street     NVARCHAR(150),
    @CustomerID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF EXISTS (SELECT 1 FROM Customer WHERE Email = @Email)
            THROW 50040, 'This email is already registered.', 1;

        BEGIN TRANSACTION;

        INSERT INTO Customer (FirstName, LastName, Email, Phone)
        VALUES (@FirstName, @LastName, @Email, @Phone);

        DECLARE @NewID INT = SCOPE_IDENTITY();

        INSERT INTO Address (CustomerID, City, Street, IsDefault)
        VALUES (@NewID, @City, @Street, 1);

        COMMIT TRANSACTION;
        SET @CustomerID = @NewID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @CustomerID = NULL;
        THROW;
    END CATCH
END;
GO

-- P2. Add a product to the cart (creates the cart if needed, checks stock)
CREATE OR ALTER PROCEDURE usp_AddToCart
    @CustomerID INT,
    @ProductID  INT,
    @Qty        INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Qty <= 0
        THROW 50030, 'Quantity must be greater than zero.', 1;

    IF NOT EXISTS (SELECT 1 FROM Customer WHERE CustomerID = @CustomerID AND IsActive = 1)
        THROW 50001, 'Customer not found or inactive.', 1;

    DECLARE @Stock INT = (SELECT StockQty FROM Product WHERE ProductID = @ProductID);
    IF @Stock IS NULL
        THROW 50031, 'Product not found.', 1;

    DECLARE @CartID INT = (SELECT CartID FROM Cart WHERE CustomerID = @CustomerID);
    IF @CartID IS NULL
    BEGIN
        INSERT INTO Cart (CustomerID) VALUES (@CustomerID);
        SET @CartID = SCOPE_IDENTITY();
    END

    DECLARE @InCart INT = ISNULL((SELECT Qty FROM CartItem WHERE CartID = @CartID AND ProductID = @ProductID), 0);

    IF @InCart + @Qty > @Stock
        THROW 50032, 'Requested quantity exceeds available stock.', 1;

    IF @InCart = 0
        INSERT INTO CartItem (CartID, ProductID, Qty) VALUES (@CartID, @ProductID, @Qty);
    ELSE
        UPDATE CartItem SET Qty = Qty + @Qty WHERE CartID = @CartID AND ProductID = @ProductID;
END;
GO

-- P3. Turn the cart into an order (the main business procedure)
--     order + items + pending payment are created in ONE transaction.
--     Stock is checked/reduced by trg_OrderItem_ReduceStock.
--     Loyalty discount comes from fn_GetCustomerDiscount.
CREATE OR ALTER PROCEDURE usp_PlaceOrder
    @CustomerID    INT,
    @PaymentMethod VARCHAR(30),
    @AddressID     INT = NULL,          -- NULL = use the default address
    @OrderID       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Customer WHERE CustomerID = @CustomerID AND IsActive = 1)
            THROW 50001, 'Customer not found or inactive.', 1;

        DECLARE @CartID INT = (SELECT CartID FROM Cart WHERE CustomerID = @CustomerID);
        IF @CartID IS NULL OR NOT EXISTS (SELECT 1 FROM CartItem WHERE CartID = @CartID)
            THROW 50002, 'Cart is empty.', 1;

        IF @AddressID IS NULL
            SELECT @AddressID = AddressID FROM Address WHERE CustomerID = @CustomerID AND IsDefault = 1;

        IF @AddressID IS NULL OR NOT EXISTS (SELECT 1 FROM Address WHERE AddressID = @AddressID AND CustomerID = @CustomerID)
            THROW 50003, 'Invalid address for this customer.', 1;

        DECLARE @Discount DECIMAL(4,2) = dbo.fn_GetCustomerDiscount(@CustomerID);
        DECLARE @Subtotal DECIMAL(12,2);
        DECLARE @NewOrderID INT;

        BEGIN TRANSACTION;

        INSERT INTO Orders (CustomerID, AddressID, Status, TotalAmount)
        VALUES (@CustomerID, @AddressID, 'Pending', 0);

        SET @NewOrderID = SCOPE_IDENTITY();

        -- copy cart items using the CURRENT product price (the trigger checks and reduces stock)
        INSERT INTO OrderItem (OrderID, ProductID, Qty, UnitPrice)
        SELECT @NewOrderID, ci.ProductID, ci.Qty, p.Price
        FROM CartItem ci
        JOIN Product p ON p.ProductID = ci.ProductID
        WHERE ci.CartID = @CartID;

        SELECT @Subtotal = SUM(Qty * UnitPrice) FROM OrderItem WHERE OrderID = @NewOrderID;

        UPDATE Orders
        SET TotalAmount = ROUND(@Subtotal * (1 - @Discount), 2)
        WHERE OrderID = @NewOrderID;

        INSERT INTO Payment (OrderID, Method, Amount, Status)
        SELECT OrderID, @PaymentMethod, TotalAmount, 'Pending'
        FROM Orders
        WHERE OrderID = @NewOrderID;

        DELETE FROM CartItem WHERE CartID = @CartID;

        COMMIT TRANSACTION;
        SET @OrderID = @NewOrderID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @OrderID = NULL;
        THROW;
    END CATCH
END;
GO

-- P4. Confirm payment (trigger then moves the order from Pending to Paid)
CREATE OR ALTER PROCEDURE usp_ConfirmPayment
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM Orders WHERE OrderID = @OrderID)
        THROW 50050, 'Order not found.', 1;

    IF NOT EXISTS (SELECT 1 FROM Payment WHERE OrderID = @OrderID AND Status = 'Pending')
        THROW 50051, 'There is no pending payment for this order.', 1;

    UPDATE Payment
    SET Status = 'Completed', PaymentDate = GETDATE()
    WHERE OrderID = @OrderID AND Status = 'Pending';
END;
GO

-- P5. Move an order forward (Shipped / Delivered). Logging and rules live in the trigger.
CREATE OR ALTER PROCEDURE usp_UpdateOrderStatus
    @OrderID   INT,
    @NewStatus VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM Orders WHERE OrderID = @OrderID)
        THROW 50060, 'Order not found.', 1;

    IF @NewStatus = 'Cancelled'
        THROW 50061, 'Use usp_CancelOrder to cancel an order.', 1;

    UPDATE Orders SET Status = @NewStatus WHERE OrderID = @OrderID;
END;
GO

-- P6. Cancel an order: status -> Cancelled (stock restored by trigger), payment refunded/failed
CREATE OR ALTER PROCEDURE usp_CancelOrder
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status VARCHAR(20) = (SELECT Status FROM Orders WHERE OrderID = @OrderID);

    IF @Status IS NULL
        THROW 50020, 'Order not found.', 1;

    IF @Status IN ('Shipped', 'Delivered', 'Cancelled')
        THROW 50021, 'This order can no longer be cancelled.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE Orders SET Status = 'Cancelled' WHERE OrderID = @OrderID;

        UPDATE Payment
        SET Status = CASE WHEN Status = 'Completed' THEN 'Refunded' ELSE 'Failed' END
        WHERE OrderID = @OrderID AND Status IN ('Pending', 'Completed');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- P7. Add a review (only for products from a delivered order, once per product)
CREATE OR ALTER PROCEDURE usp_AddReview
    @CustomerID INT,
    @ProductID  INT,
    @Rating     TINYINT,
    @Comment    NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM Orders o
        JOIN OrderItem oi ON oi.OrderID = o.OrderID
        WHERE o.CustomerID = @CustomerID AND oi.ProductID = @ProductID AND o.Status = 'Delivered'
    )
        THROW 50070, 'You can only review products from delivered orders.', 1;

    IF EXISTS (SELECT 1 FROM Review WHERE CustomerID = @CustomerID AND ProductID = @ProductID)
        THROW 50071, 'You have already reviewed this product.', 1;

    INSERT INTO Review (ProductID, CustomerID, Rating, Comment)
    VALUES (@ProductID, @CustomerID, @Rating, @Comment);
END;
GO

-- P8. Restock a product
CREATE OR ALTER PROCEDURE usp_RestockProduct
    @ProductID INT,
    @Qty       INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @Qty <= 0
        THROW 50080, 'Quantity must be greater than zero.', 1;

    UPDATE Product SET StockQty = StockQty + @Qty WHERE ProductID = @ProductID;

    IF @@ROWCOUNT = 0
        THROW 50081, 'Product not found.', 1;
END;
GO

-- P9. Sales report for a date range (returns 2 result sets). Default: last month.
CREATE OR ALTER PROCEDURE usp_SalesReport
    @FromDate DATE = NULL,
    @ToDate   DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @ToDate   = ISNULL(@ToDate, CAST(GETDATE() AS DATE));
    SET @FromDate = ISNULL(@FromDate, DATEADD(MONTH, -1, @ToDate));

    -- Result set 1: summary
    SELECT COUNT(*)                                       AS Orders,
           ISNULL(SUM(TotalAmount), 0)                    AS Revenue,
           ISNULL(CAST(AVG(TotalAmount) AS DECIMAL(12,2)), 0) AS AvgOrderValue,
           COUNT(DISTINCT CustomerID)                     AS Customers
    FROM Orders
    WHERE Status <> 'Cancelled'
      AND OrderDate >= @FromDate AND OrderDate < DATEADD(DAY, 1, @ToDate);

    -- Result set 2: revenue per category
    SELECT CategoryName, SUM(Qty) AS Units, SUM(LineTotal) AS Revenue
    FROM vw_OrderDetails
    WHERE Status <> 'Cancelled'
      AND OrderDate >= @FromDate AND OrderDate < DATEADD(DAY, 1, @ToDate)
    GROUP BY CategoryName
    ORDER BY Revenue DESC;
END;
GO

/* ============================================================
   4) TESTS  (run this whole section as ONE batch and read the outputs)
   Flow: new customer -> cart -> place order -> pay -> try to oversell
         -> cancel -> try an illegal status change -> read the audit log
   ============================================================ */
DECLARE @cid INT, @oid INT, @pA INT, @pB INT, @pC INT, @email NVARCHAR(100);

SET @email = 'demo.' + FORMAT(SYSDATETIME(), 'yyyyMMddHHmmssfff') + '@example.com';
SELECT @pA = ProductID FROM Product WHERE Name = 'The Alchemist';
SELECT @pB = ProductID FROM Product WHERE Name = 'Yoga Mat';
SELECT @pC = ProductID FROM Product WHERE Name = 'Resistance Bands Set';

PRINT '--- 1) Stock BEFORE the order';
SELECT ProductID, Name, StockQty FROM Product WHERE ProductID IN (@pA, @pB);

PRINT '--- 2) Create customer, fill cart, place order';
EXEC usp_AddCustomer 'Demo', 'Customer', @email, '01012345678', 'Cairo', '15 Tahrir St', @cid OUTPUT;
EXEC usp_AddToCart @cid, @pA, 2;
EXEC usp_AddToCart @cid, @pB, 1;
EXEC usp_PlaceOrder @cid, 'Fawry', NULL, @oid OUTPUT;

SELECT OrderID, CustomerID, Status, TotalAmount FROM Orders WHERE OrderID = @oid;
SELECT * FROM OrderItem WHERE OrderID = @oid;
SELECT PaymentID, Method, Amount, Status FROM Payment WHERE OrderID = @oid;

PRINT '--- 3) Stock AFTER the order (reduced by the trigger)';
SELECT ProductID, Name, StockQty FROM Product WHERE ProductID IN (@pA, @pB);

PRINT '--- 4) Confirm payment -> order should become Paid';
EXEC usp_ConfirmPayment @oid;
SELECT Status FROM Orders WHERE OrderID = @oid;

PRINT '--- 5) Try to oversell: trigger must reject it';
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO OrderItem (OrderID, ProductID, Qty, UnitPrice)
    SELECT @oid, ProductID, 99999, Price FROM Product WHERE ProductID = @pC;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Rejected as expected: ' + ERROR_MESSAGE();
END CATCH

PRINT '--- 6) Cancel the order -> stock restored, payment refunded';
EXEC usp_CancelOrder @oid;
SELECT ProductID, Name, StockQty FROM Product WHERE ProductID IN (@pA, @pB);
SELECT Status FROM Payment WHERE OrderID = @oid;

PRINT '--- 7) Try to re-open the cancelled order: must be rejected';
BEGIN TRY
    EXEC usp_UpdateOrderStatus @oid, 'Shipped';
END TRY
BEGIN CATCH
    PRINT 'Rejected as expected: ' + ERROR_MESSAGE();
END CATCH

PRINT '--- 8) Audit log of this order';
SELECT * FROM OrderStatusLog WHERE OrderID = @oid ORDER BY LogID;

PRINT '--- 9) Soft delete: DELETE only deactivates the customer';
DELETE FROM Customer WHERE CustomerID = @cid;
SELECT CustomerID, Email, IsActive FROM Customer WHERE CustomerID = @cid;

PRINT '--- 10) Price history trigger';
UPDATE Product SET Price = Price + 10 WHERE ProductID = @pB;
SELECT * FROM PriceHistory WHERE ProductID = @pB;
UPDATE Product SET Price = Price - 10 WHERE ProductID = @pB;   -- put the price back

PRINT '--- 11) Sales report for the last 12 months';
DECLARE @from DATE = DATEADD(YEAR, -1, GETDATE());
EXEC usp_SalesReport @from, NULL;
GO
