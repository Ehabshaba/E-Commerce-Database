USE [E-commerce];

CREATE TABLE Customer (
    CustomerID   INT IDENTITY(1,1) CONSTRAINT PK_Customer PRIMARY KEY,
    FirstName    NVARCHAR(50)  NOT NULL,
    LastName     NVARCHAR(50)  NOT NULL,
    Email        NVARCHAR(100) NOT NULL
                 CONSTRAINT UQ_Customer_Email UNIQUE
                 CONSTRAINT CK_Customer_Email CHECK (Email LIKE '%_@_%._%'),
    Phone        VARCHAR(15)   NULL
                 CONSTRAINT CK_Customer_Phone CHECK (Phone NOT LIKE '%[^0-9+]%'),
    RegisterDate DATETIME      NOT NULL CONSTRAINT DF_Customer_RegisterDate DEFAULT GETDATE(),
    IsActive     BIT           NOT NULL CONSTRAINT DF_Customer_IsActive DEFAULT 1
);

CREATE TABLE Address (
    AddressID  INT IDENTITY(1,1) CONSTRAINT PK_Address PRIMARY KEY,
    CustomerID INT           NOT NULL
               CONSTRAINT FK_Address_Customer REFERENCES Customer(CustomerID) ON DELETE CASCADE,
    City       NVARCHAR(50)  NOT NULL,
    Street     NVARCHAR(150) NOT NULL,
    IsDefault  BIT           NOT NULL CONSTRAINT DF_Address_IsDefault DEFAULT 0
);

-- A customer can have only ONE default address
CREATE UNIQUE INDEX UX_Address_OneDefault ON Address(CustomerID) WHERE IsDefault = 1;


CREATE TABLE Category (
    CategoryID       INT IDENTITY(1,1) CONSTRAINT PK_Category PRIMARY KEY,
    Name             NVARCHAR(80) NOT NULL CONSTRAINT UQ_Category_Name UNIQUE,
    ParentCategoryID INT NULL
                     CONSTRAINT FK_Category_Parent REFERENCES Category(CategoryID)   -- self reference
);

CREATE TABLE Supplier (
    SupplierID INT IDENTITY(1,1) CONSTRAINT PK_Supplier PRIMARY KEY,
    Name       NVARCHAR(100) NOT NULL CONSTRAINT UQ_Supplier_Name UNIQUE,
    Phone      VARCHAR(15)   NULL,
    Email      NVARCHAR(100) NOT NULL CONSTRAINT UQ_Supplier_Email UNIQUE
);


CREATE TABLE Product (
    ProductID   INT IDENTITY(1,1) CONSTRAINT PK_Product PRIMARY KEY,
    Name        NVARCHAR(150)  NOT NULL CONSTRAINT UQ_Product_Name UNIQUE,
    Price       DECIMAL(10,2)  NOT NULL CONSTRAINT CK_Product_Price CHECK (Price > 0),
    StockQty    INT            NOT NULL CONSTRAINT DF_Product_Stock DEFAULT 0
                CONSTRAINT CK_Product_Stock CHECK (StockQty >= 0),
    CategoryID  INT NOT NULL CONSTRAINT FK_Product_Category REFERENCES Category(CategoryID),
    SupplierID  INT NOT NULL CONSTRAINT FK_Product_Supplier REFERENCES Supplier(SupplierID),
    CreatedDate DATETIME NOT NULL CONSTRAINT DF_Product_Created DEFAULT GETDATE()
);


CREATE TABLE Cart (
    CartID      INT IDENTITY(1,1) CONSTRAINT PK_Cart PRIMARY KEY,
    CustomerID  INT NOT NULL
                CONSTRAINT UQ_Cart_Customer UNIQUE                                    -- one active cart per customer
                CONSTRAINT FK_Cart_Customer REFERENCES Customer(CustomerID) ON DELETE CASCADE,
    CreatedDate DATETIME NOT NULL CONSTRAINT DF_Cart_Created DEFAULT GETDATE()
);

CREATE TABLE CartItem (
    CartItemID INT IDENTITY(1,1) CONSTRAINT PK_CartItem PRIMARY KEY,
    CartID     INT NOT NULL CONSTRAINT FK_CartItem_Cart REFERENCES Cart(CartID) ON DELETE CASCADE,
    ProductID  INT NOT NULL CONSTRAINT FK_CartItem_Product REFERENCES Product(ProductID),
    Qty        INT NOT NULL CONSTRAINT CK_CartItem_Qty CHECK (Qty > 0),
    CONSTRAINT UQ_CartItem_Cart_Product UNIQUE (CartID, ProductID)
);


CREATE TABLE Orders (
    OrderID     INT IDENTITY(1,1) CONSTRAINT PK_Orders PRIMARY KEY,
    CustomerID  INT NOT NULL CONSTRAINT FK_Orders_Customer REFERENCES Customer(CustomerID),
    AddressID   INT NOT NULL CONSTRAINT FK_Orders_Address  REFERENCES Address(AddressID),
    OrderDate   DATETIME NOT NULL CONSTRAINT DF_Orders_Date DEFAULT GETDATE(),
    Status      VARCHAR(20) NOT NULL CONSTRAINT DF_Orders_Status DEFAULT 'Pending'
                CONSTRAINT CK_Orders_Status CHECK (Status IN ('Pending','Paid','Shipped','Delivered','Cancelled')),
    TotalAmount DECIMAL(12,2) NOT NULL CONSTRAINT DF_Orders_Total DEFAULT 0
                CONSTRAINT CK_Orders_Total CHECK (TotalAmount >= 0)
);


CREATE TABLE OrderItem (
    OrderItemID INT IDENTITY(1,1) CONSTRAINT PK_OrderItem PRIMARY KEY,
    OrderID     INT NOT NULL CONSTRAINT FK_OrderItem_Orders  REFERENCES Orders(OrderID) ON DELETE CASCADE,
    ProductID   INT NOT NULL CONSTRAINT FK_OrderItem_Product REFERENCES Product(ProductID),
    Qty         INT NOT NULL CONSTRAINT CK_OrderItem_Qty CHECK (Qty > 0),
    UnitPrice   DECIMAL(10,2) NOT NULL CONSTRAINT CK_OrderItem_Price CHECK (UnitPrice > 0),  -- price at purchase time
    CONSTRAINT UQ_OrderItem_Order_Product UNIQUE (OrderID, ProductID)
);


CREATE TABLE Payment (
    PaymentID   INT IDENTITY(1,1) CONSTRAINT PK_Payment PRIMARY KEY,
    OrderID     INT NOT NULL CONSTRAINT FK_Payment_Orders REFERENCES Orders(OrderID),
    Method      VARCHAR(30) NOT NULL
                CONSTRAINT CK_Payment_Method CHECK (Method IN ('Credit Card','Cash on Delivery','Vodafone Cash','Fawry')),
    Amount      DECIMAL(12,2) NOT NULL CONSTRAINT CK_Payment_Amount CHECK (Amount >= 0),
    PaymentDate DATETIME NOT NULL CONSTRAINT DF_Payment_Date DEFAULT GETDATE(),
    Status      VARCHAR(20) NOT NULL CONSTRAINT DF_Payment_Status DEFAULT 'Pending'
                CONSTRAINT CK_Payment_Status CHECK (Status IN ('Pending','Completed','Failed','Refunded'))
);


CREATE TABLE Review (
    ReviewID   INT IDENTITY(1,1) CONSTRAINT PK_Review PRIMARY KEY,
    ProductID  INT NOT NULL CONSTRAINT FK_Review_Product  REFERENCES Product(ProductID),
    CustomerID INT NOT NULL CONSTRAINT FK_Review_Customer REFERENCES Customer(CustomerID),
    Rating     TINYINT NOT NULL CONSTRAINT CK_Review_Rating CHECK (Rating BETWEEN 1 AND 5),
    Comment    NVARCHAR(500) NULL,
    ReviewDate DATETIME NOT NULL CONSTRAINT DF_Review_Date DEFAULT GETDATE(),
    CONSTRAINT UQ_Review_Product_Customer UNIQUE (ProductID, CustomerID)   -- one review per customer per product
);

---------------------------------------------------------------
---------------------------------------------------------------

CREATE TABLE #FirstNames (id INT, name NVARCHAR(50));
INSERT INTO #FirstNames VALUES
(1,'Ahmed'),(2,'Mohamed'),(3,'Mahmoud'),(4,'Omar'),(5,'Ali'),(6,'Youssef'),(7,'Karim'),(8,'Hassan'),(9,'Mostafa'),(10,'Ibrahim'),
(11,'Fatma'),(12,'Sara'),(13,'Nour'),(14,'Mariam'),(15,'Hana'),(16,'Aya'),(17,'Salma'),(18,'Rana'),(19,'Dina'),(20,'Yasmin');

CREATE TABLE #LastNames (id INT, name NVARCHAR(50));
INSERT INTO #LastNames VALUES
(1,'Hassan'),(2,'Ibrahim'),(3,'Mansour'),(4,'Said'),(5,'Farouk'),(6,'Nasser'),(7,'Khalil'),(8,'Fahmy'),(9,'Gamal'),(10,'Salem');

CREATE TABLE #Cities (id INT, name NVARCHAR(50));
INSERT INTO #Cities VALUES
(1,'Cairo'),(2,'Giza'),(3,'Alexandria'),(4,'Mansoura'),(5,'Tanta'),(6,'Aswan'),(7,'Luxor'),(8,'Port Said'),(9,'Suez'),(10,'Ismailia');

CREATE TABLE #Streets (id INT, name NVARCHAR(60));
INSERT INTO #Streets VALUES
(1,'Tahrir St'),(2,'Nile Corniche'),(3,'Al-Haram St'),(4,'Salah Salem St'),(5,'El-Nahas St'),
(6,'El-Gomhoria St'),(7,'Abbas El-Akkad St'),(8,'26th of July St'),(9,'Al-Azhar St'),(10,'El-Thawra St');

SELECT * FROM Customer
SELECT * FROM #FirstNames
SELECT * FROM Category

INSERT INTO Category (Name, ParentCategoryID) VALUES
('Electronics',NULL),('Fashion',NULL),('Home & Kitchen',NULL),('Books',NULL),('Sports',NULL);

INSERT INTO Category (Name, ParentCategoryID)
SELECT v.Name, p.CategoryID
FROM (VALUES
    ('Mobile Phones','Electronics'),('Laptops','Electronics'),('Headphones','Electronics'),
    ('Men Clothing','Fashion'),('Women Clothing','Fashion'),('Shoes','Fashion'),
    ('Cookware','Home & Kitchen'),('Furniture','Home & Kitchen'),
    ('Programming Books','Books'),('Novels','Books'),
    ('Fitness Equipment','Sports'),('Outdoor','Sports')
) v(Name, ParentName)
JOIN Category p ON p.Name = v.ParentName;

INSERT INTO Supplier (Name, Phone, Email) VALUES
('Cairo Tech Distribution','01012345678','sales@cairotech.example.com'),
('Delta Electronics','01123456789','info@deltaelec.example.com'),
('Nile Fashion House','01234567890','orders@nilefashion.example.com'),
('Alex Home Supplies','01098765432','contact@alexhome.example.com'),
('Pyramid Books','01187654321','books@pyramidbooks.example.com'),
('Sphinx Sports','01276543210','team@sphinxsports.example.com'),
('Giza Trading','01055556666','hello@gizatrading.example.com'),
('Horus Wholesale','01166667777','wholesale@horus.example.com');


INSERT INTO Product (Name, Price, StockQty, CategoryID, SupplierID)
SELECT v.Name, v.Price, v.Stock, c.CategoryID, s.SupplierID
FROM (VALUES
    ('Samsung Galaxy A55',14500.00, 80,'Mobile Phones','Delta Electronics'),
    ('iPhone 14 128GB',   32000.00, 40,'Mobile Phones','Cairo Tech Distribution'),
    ('Xiaomi Redmi Note 13',8200.00,150,'Mobile Phones','Giza Trading'),
    ('Lenovo IdeaPad 3',  19500.00, 35,'Laptops','Delta Electronics'),
    ('HP Pavilion 15',    24500.00, 28,'Laptops','Cairo Tech Distribution'),
    ('Dell Inspiron 15',  22000.00, 30,'Laptops','Cairo Tech Distribution'),
    ('Sony WH-CH520',      2300.00,120,'Headphones','Delta Electronics'),
    ('JBL Tune 510BT',     1400.00,200,'Headphones','Delta Electronics'),
    ('Anker Soundcore Q20i',2600.00, 90,'Headphones','Giza Trading'),
    ('Cotton Polo Shirt',   350.00,400,'Men Clothing','Nile Fashion House'),
    ('Slim Fit Jeans',      650.00,300,'Men Clothing','Nile Fashion House'),
    ('Winter Hoodie',       720.00,250,'Men Clothing','Nile Fashion House'),
    ('Floral Summer Dress', 800.00,180,'Women Clothing','Nile Fashion House'),
    ('Casual Abaya',       1100.00,140,'Women Clothing','Nile Fashion House'),
    ('Knit Cardigan',       560.00,210,'Women Clothing','Horus Wholesale'),
    ('Running Sneakers',   1250.00,170,'Shoes','Sphinx Sports'),
    ('Leather Loafers',    1500.00, 95,'Shoes','Horus Wholesale'),
    ('Classic Sandals',     300.00,320,'Shoes','Horus Wholesale'),
    ('Non-stick Pan 28cm',  420.00,260,'Cookware','Alex Home Supplies'),
    ('Pressure Cooker 6L', 1350.00, 75,'Cookware','Alex Home Supplies'),
    ('Stainless Steel Pot Set',2100.00,60,'Cookware','Alex Home Supplies'),
    ('Office Desk',        3200.00, 45,'Furniture','Alex Home Supplies'),
    ('Ergonomic Chair',    4100.00, 38,'Furniture','Giza Trading'),
    ('3-Door Wardrobe',    7800.00, 20,'Furniture','Alex Home Supplies'),
    ('Clean Code',          950.00,110,'Programming Books','Pyramid Books'),
    ('SQL Server Fundamentals',600.00,130,'Programming Books','Pyramid Books'),
    ('Python Crash Course', 700.00,125,'Programming Books','Pyramid Books'),
    ('The Alchemist',       280.00,220,'Novels','Pyramid Books'),
    ('Season of Migration to the North',240.00,150,'Novels','Pyramid Books'),
    ('Children of the Alley',260.00,160,'Novels','Pyramid Books'),
    ('Adjustable Dumbbells 20kg',1800.00,65,'Fitness Equipment','Sphinx Sports'),
    ('Yoga Mat',            250.00,280,'Fitness Equipment','Sphinx Sports'),
    ('Resistance Bands Set',200.00,300,'Fitness Equipment','Sphinx Sports'),
    ('4-Person Camping Tent',2700.00,42,'Outdoor','Sphinx Sports'),
    ('Hiking Backpack 40L',1300.00,85,'Outdoor','Horus Wholesale'),
    ('Insulated Water Bottle',310.00,350,'Outdoor','Giza Trading')
) v(Name, Price, Stock, CategoryName, SupplierName)
JOIN Category c ON c.Name = v.CategoryName
JOIN Supplier s ON s.Name = v.SupplierName;

WITH N AS (
    SELECT TOP (200) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO Customer (FirstName, LastName, Email, Phone, RegisterDate)
SELECT f.name, l.name,
       LOWER(f.name + '.' + l.name) + CAST(N.n AS VARCHAR(5)) + '@example.com',
       '01' + CHOOSE(N.n % 4 + 1, '0','1','2','5')
            + RIGHT('00000000' + CAST(ABS(CHECKSUM(NEWID())) % 100000000 AS VARCHAR(8)), 8),
       DATEADD(DAY, -(ABS(CHECKSUM(NEWID())) % 364 + 1), GETDATE())
FROM N
JOIN #FirstNames f ON f.id = (N.n - 1) % 20 + 1
JOIN #LastNames  l ON l.id = ((N.n - 1) / 20) % 10 + 1;

INSERT INTO Address (CustomerID, City, Street, IsDefault)
SELECT c.CustomerID, ct.name,
       CAST((c.CustomerID * 13) % 200 + 1 AS VARCHAR(5)) + ' ' + st.name, 1
FROM Customer c
JOIN #Cities  ct ON ct.id = c.CustomerID % 10 + 1
JOIN #Streets st ON st.id = (c.CustomerID * 3) % 10 + 1;

INSERT INTO Address (CustomerID, City, Street, IsDefault)
SELECT c.CustomerID, ct.name,
       CAST((c.CustomerID * 7) % 150 + 1 AS VARCHAR(5)) + ' ' + st.name, 0
FROM Customer c
JOIN #Cities  ct ON ct.id = (c.CustomerID + 4) % 10 + 1
JOIN #Streets st ON st.id = (c.CustomerID * 7) % 10 + 1
WHERE c.CustomerID % 3 = 0;


INSERT INTO Cart (CustomerID, CreatedDate)
SELECT CustomerID, DATEADD(DAY, -(CustomerID % 20), GETDATE())
FROM Customer
WHERE CustomerID % 3 = 1;

INSERT INTO CartItem (CartID, ProductID, Qty)
SELECT c.CartID, (c.CartID * 5 + k.k * 7) % 36 + 1, c.CartID % 3 + 1
FROM Cart c
CROSS JOIN (VALUES (0),(1)) k(k);


WITH N AS (
    SELECT TOP (600) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
SELECT n,
       ABS(CHECKSUM(NEWID())) % 200 + 1 AS CustomerID,
       ABS(CHECKSUM(NEWID())) % 100     AS r
INTO #O
FROM N;

INSERT INTO Orders (CustomerID, AddressID, OrderDate, Status, TotalAmount)
SELECT o.CustomerID, a.AddressID,
       DATEADD(SECOND, ABS(CHECKSUM(NEWID())) % DATEDIFF(SECOND, c.RegisterDate, GETDATE()), c.RegisterDate),
       CASE WHEN o.r < 8  THEN 'Cancelled'
            WHEN o.r < 15 THEN 'Pending'
            WHEN o.r < 25 THEN 'Paid'
            WHEN o.r < 40 THEN 'Shipped'
            ELSE 'Delivered' END,
       0
FROM #O o
JOIN Customer c ON c.CustomerID = o.CustomerID
JOIN Address  a ON a.CustomerID = o.CustomerID AND a.IsDefault = 1;


SELECT OrderID,
       ABS(CHECKSUM(NEWID())) % 36 AS base,
       ABS(CHECKSUM(NEWID())) % 4 + 1 AS itemCount
INTO #OB
FROM Orders;

INSERT INTO OrderItem (OrderID, ProductID, Qty, UnitPrice)
SELECT ob.OrderID, p.ProductID, ABS(CHECKSUM(NEWID())) % 3 + 1, p.Price
FROM #OB ob
JOIN (VALUES (1),(2),(3),(4)) k(k) ON k.k <= ob.itemCount
JOIN Product p ON p.ProductID = (ob.base + k.k * 9) % 36 + 1;


UPDATE o
SET TotalAmount = t.Total
FROM Orders o
JOIN (SELECT OrderID, SUM(Qty * UnitPrice) AS Total FROM OrderItem GROUP BY OrderID) t
  ON t.OrderID = o.OrderID;


SELECT OrderID,
       ABS(CHECKSUM(NEWID())) % 4 + 1 AS m,
       ABS(CHECKSUM(NEWID())) % 120   AS mins
INTO #PM
FROM Orders;

INSERT INTO Payment (OrderID, Method, Amount, PaymentDate, Status)
SELECT o.OrderID,
       CHOOSE(pm.m, 'Credit Card','Cash on Delivery','Vodafone Cash','Fawry'),
       o.TotalAmount,
       DATEADD(MINUTE, 5 + pm.mins, o.OrderDate),
       CASE WHEN o.Status = 'Cancelled' THEN CASE WHEN o.OrderID % 2 = 0 THEN 'Refunded' ELSE 'Failed' END
            WHEN o.Status = 'Pending'   THEN 'Pending'
            ELSE 'Completed' END
FROM Orders o
JOIN #PM pm ON pm.OrderID = o.OrderID;

DROP TABLE #PM;

SELECT COUNT(*) FROM Payment; 

WITH D AS (
    SELECT oi.ProductID, o.CustomerID, o.OrderDate,
           ROW_NUMBER() OVER (PARTITION BY oi.ProductID, o.CustomerID ORDER BY o.OrderDate) AS rn
    FROM OrderItem oi
    JOIN Orders o ON o.OrderID = oi.OrderID
    WHERE o.Status = 'Delivered'
      AND o.OrderDate < DATEADD(DAY, -11, GETDATE())
)
SELECT ProductID, CustomerID, OrderDate, ABS(CHECKSUM(NEWID())) % 100 AS r
INTO #R
FROM D
WHERE rn = 1 AND ABS(CHECKSUM(NEWID())) % 100 < 50;

INSERT INTO Review (ProductID, CustomerID, Rating, Comment, ReviewDate)
SELECT ProductID, CustomerID, Rating,
       CHOOSE(Rating,
              'Very disappointed, not as described.',
              'Below expectations.',
              'Okay for the price.',
              'Good product, would buy again.',
              'Excellent quality, highly recommended!'),
       DATEADD(DAY, 1 + ABS(CHECKSUM(NEWID())) % 10, OrderDate)
FROM (
    SELECT ProductID, CustomerID, OrderDate,
           CASE WHEN r < 5 THEN 1 WHEN r < 12 THEN 2 WHEN r < 25 THEN 3 WHEN r < 55 THEN 4 ELSE 5 END AS Rating
    FROM #R
) x;


DROP TABLE #FirstNames, #LastNames, #Cities, #Streets, #O, #OB, #R;

SELECT 'Customer'  AS TableName, COUNT(*) AS Rows FROM Customer  UNION ALL
SELECT 'Address',   COUNT(*) FROM Address   UNION ALL
SELECT 'Category',  COUNT(*) FROM Category  UNION ALL
SELECT 'Supplier',  COUNT(*) FROM Supplier  UNION ALL
SELECT 'Product',   COUNT(*) FROM Product   UNION ALL
SELECT 'Cart',      COUNT(*) FROM Cart      UNION ALL
SELECT 'CartItem',  COUNT(*) FROM CartItem  UNION ALL
SELECT 'Orders',    COUNT(*) FROM Orders    UNION ALL
SELECT 'OrderItem', COUNT(*) FROM OrderItem UNION ALL
SELECT 'Payment',   COUNT(*) FROM Payment   UNION ALL
SELECT 'Review',    COUNT(*) FROM Review;

SELECT * FROM Customer
SELECT * FROM Address
SELECT * FROM Category
SELECT * FROM Supplier
SELECT * FROM Product
SELECT * FROM Cart
SELECT * FROM CartItem
SELECT * FROM Orders
SELECT * FROM OrderItem
SELECT * FROM Payment
SELECT * FROM Review
