---
layout: post
title: sqlite and sqlc with claude
categories: [golang, sqlite, sqlc]
tags: [golang, sqlite, sqlc]
---
# Building Production-grade Data Layers in Go with sqlc and SQLite

## Executive Summary

SQLite has evolved from a development convenience to a legitimate production database choice for many applications in 2025. When combined with sqlc's type-safe code generation, Go developers can build robust, maintainable data layers that rival traditional ORM-based solutions while maintaining superior performance characteristics. This comprehensive guide explores building production-grade data access layers using SQLite as the primary database engine, sqlc for type-safe query generation, and modern Go patterns including context propagation, structured error handling, and comprehensive testing strategies.

The approach detailed here emphasizes clean architecture principles, separating concerns between data access, business logic, and presentation layers. We examine advanced SQLite configurations including WAL mode, connection pooling, and backup strategies using Litestream. The guide covers practical implementation patterns for repository and service layers, demonstrates integration with golang-migrate for schema versioning, and provides battle-tested testing approaches that ensure data layer reliability.

Key architectural decisions include leveraging sqlc's compile-time type safety to eliminate runtime query errors, implementing comprehensive error handling with wrapped errors and context cancellation, and utilizing SQLite's advanced features for optimal performance. The resulting system provides the simplicity of SQLite with the robustness required for production workloads, particularly suited for applications with moderate write loads and high read requirements.

## Introduction: The Case for SQLite and sqlc in 2025

The database landscape has undergone significant evolution over the past decade. While PostgreSQL and MySQL remain dominant for large-scale applications, SQLite has emerged as a compelling choice for a substantial category of production systems. The combination of SQLite's simplicity, reliability, and performance characteristics with sqlc's type-safe code generation creates a powerful foundation for modern Go applications.

### Why SQLite in Production?

SQLite's reputation as merely a development or embedded database has been challenged by real-world production deployments. Major companies including Apple, Airbnb, and Figma leverage SQLite for production workloads, demonstrating its viability beyond toy applications. The key advantages that make SQLite production-worthy include its serverless architecture, which eliminates network latency and connection overhead, its exceptional read performance that often exceeds traditional client-server databases, and its operational simplicity that reduces infrastructure complexity.

SQLite's ACID compliance, mature codebase with extensive testing, and support for advanced features like window functions, common table expressions, and partial indexes make it suitable for sophisticated applications. The introduction of WAL mode significantly improved concurrent read performance while maintaining write serialization, addressing one of the primary concerns about SQLite's suitability for multi-user applications.

### The sqlc Advantage

Traditional ORMs introduce runtime overhead, complex abstraction layers, and often generate suboptimal queries. sqlc takes a different approach by generating type-safe Go code from SQL queries at compile time. This approach provides several critical advantages for production systems. First, it eliminates the runtime overhead associated with reflection-based ORMs while maintaining full SQL expressiveness. Second, it provides compile-time type safety, catching schema mismatches and query errors during development rather than in production. Third, it encourages writing optimal SQL queries since developers work directly with SQL rather than through abstraction layers.

The generated code is idiomatic Go that integrates seamlessly with standard database/sql patterns, making it familiar to experienced Go developers. sqlc supports advanced SQL features including window functions, CTEs, and complex joins, enabling developers to leverage the full power of modern SQL while maintaining type safety.

### Architectural Philosophy

The approach presented in this guide embraces several key architectural principles that are essential for production systems. Clean architecture principles guide the separation of concerns, ensuring that database implementation details don't leak into business logic. The repository pattern provides a clear abstraction layer that can be easily tested and potentially swapped for different implementations. Context-driven design ensures proper cancellation and timeout handling throughout the data layer.

Error handling receives particular attention, with wrapped errors providing context for debugging while maintaining clear error boundaries between layers. The design emphasizes observability through structured logging and metrics collection, enabling effective monitoring and debugging in production environments.

## Project Architecture and Directory Layout

Establishing a clear project structure is fundamental to maintaining code quality as applications grow. The directory layout should reflect the clean architecture principles while remaining intuitive for developers joining the project.

```
project-root/
├── cmd/
│   ├── server/
│   │   └── main.go
│   └── migrate/
│       └── main.go
├── internal/
│   ├── config/
│   │   └── config.go
│   ├── database/
│   │   ├── migrations/
│   │   │   ├── 001_initial_schema.up.sql
│   │   │   ├── 001_initial_schema.down.sql
│   │   │   ├── 002_add_indexes.up.sql
│   │   │   └── 002_add_indexes.down.sql
│   │   ├── queries/
│   │   │   ├── users.sql
│   │   │   ├── orders.sql
│   │   │   └── products.sql
│   │   ├── sqlc/
│   │   │   ├── db.go
│   │   │   ├── models.go
│   │   │   ├── users.sql.go
│   │   │   ├── orders.sql.go
│   │   │   └── products.sql.go
│   │   └── connection.go
│   ├── repository/
│   │   ├── interfaces.go
│   │   ├── user_repository.go
│   │   ├── order_repository.go
│   │   └── product_repository.go
│   ├── service/
│   │   ├── user_service.go
│   │   ├── order_service.go
│   │   └── product_service.go
│   ├── handler/
│   │   ├── user_handler.go
│   │   ├── order_handler.go
│   │   └── product_handler.go
│   └── domain/
│       ├── user.go
│       ├── order.go
│       └── product.go
├── pkg/
│   ├── logger/
│   │   └── logger.go
│   ├── errors/
│   │   └── errors.go
│   └── validator/
│       └── validator.go
├── configs/
│   ├── local.yaml
│   ├── staging.yaml
│   └── production.yaml
├── scripts/
│   ├── setup.sh
│   └── migrate.sh
├── tests/
│   ├── integration/
│   │   ├── database_test.go
│   │   ├── user_repository_test.go
│   │   └── fixtures/
│   │       └── test_data.sql
│   └── unit/
│       ├── user_service_test.go
│       └── order_service_test.go
├── sqlc.yaml
├── go.mod
├── go.sum
├── docker-compose.yml
└── README.md
```

### Understanding the Architecture Layers

The directory structure reflects a layered architecture where each layer has specific responsibilities and clear boundaries. The `cmd` directory contains application entry points, separating the main server application from utility commands like database migration tools. This separation allows for building multiple binaries from the same codebase, each with focused responsibilities.

The `internal` directory houses the core application logic, ensuring that internal packages cannot be imported by external projects. Within this directory, the `database` package contains all database-related code including migrations, SQL queries, and generated sqlc code. The `repository` package provides the data access layer, implementing the repository pattern with clear interfaces that can be easily mocked for testing.

Service layer components in the `service` package contain business logic and orchestrate calls to multiple repositories when necessary. These services handle cross-cutting concerns like transaction management and complex business rules. The `handler` package contains HTTP handlers or gRPC service implementations, depending on the chosen transport layer.

Domain models in the `domain` package represent core business entities. These models are independent of database implementation details and can be shared across different layers of the application. The `pkg` directory contains reusable packages that could potentially be extracted into separate libraries, such as logging utilities, error handling helpers, and validation logic.

### Configuration Management Strategy

Configuration management requires careful consideration in production environments. The approach should support multiple environments while maintaining security for sensitive values. The configuration structure separates concerns between database connection parameters, application settings, and external service configurations.

```go
package config

import (
    "fmt"
    "os"
    "time"
    
    "gopkg.in/yaml.v3"
)

type Config struct {
    Database DatabaseConfig `yaml:"database"`
    Server   ServerConfig   `yaml:"server"`
    Logging  LoggingConfig  `yaml:"logging"`
    Features FeatureConfig  `yaml:"features"`
}

type DatabaseConfig struct {
    Path            string        `yaml:"path"`
    MaxOpenConns    int           `yaml:"max_open_conns"`
    MaxIdleConns    int           `yaml:"max_idle_conns"`
    ConnMaxLifetime time.Duration `yaml:"conn_max_lifetime"`
    BusyTimeout     time.Duration `yaml:"busy_timeout"`
    WALMode         bool          `yaml:"wal_mode"`
    SynchronousMode string        `yaml:"synchronous_mode"`
    CacheSize       int           `yaml:"cache_size"`
    TempStore       string        `yaml:"temp_store"`
    JournalMode     string        `yaml:"journal_mode"`
}

type ServerConfig struct {
    Host         string        `yaml:"host"`
    Port         int           `yaml:"port"`
    ReadTimeout  time.Duration `yaml:"read_timeout"`
    WriteTimeout time.Duration `yaml:"write_timeout"`
    IdleTimeout  time.Duration `yaml:"idle_timeout"`
}

type LoggingConfig struct {
    Level      string `yaml:"level"`
    Format     string `yaml:"format"`
    Output     string `yaml:"output"`
    Structured bool   `yaml:"structured"`
}

type FeatureConfig struct {
    EnableMetrics     bool `yaml:"enable_metrics"`
    EnableProfiler    bool `yaml:"enable_profiler"`
    EnableHealthCheck bool `yaml:"enable_health_check"`
}

func Load(configPath string) (*Config, error) {
    var cfg Config
    
    // Set defaults
    cfg.Database.MaxOpenConns = 25
    cfg.Database.MaxIdleConns = 10
    cfg.Database.ConnMaxLifetime = time.Hour
    cfg.Database.BusyTimeout = 30 * time.Second
    cfg.Database.WALMode = true
    cfg.Database.SynchronousMode = "NORMAL"
    cfg.Database.CacheSize = -64000 // 64MB
    cfg.Database.TempStore = "MEMORY"
    cfg.Database.JournalMode = "WAL"
    
    cfg.Server.Host = "localhost"
    cfg.Server.Port = 8080
    cfg.Server.ReadTimeout = 15 * time.Second
    cfg.Server.WriteTimeout = 15 * time.Second
    cfg.Server.IdleTimeout = 60 * time.Second
    
    cfg.Logging.Level = "info"
    cfg.Logging.Format = "json"
    cfg.Logging.Structured = true
    
    // Load from file if exists
    if configPath != "" {
        data, err := os.ReadFile(configPath)
        if err != nil {
            return nil, fmt.Errorf("reading config file: %w", err)
        }
        
        if err := yaml.Unmarshal(data, &cfg); err != nil {
            return nil, fmt.Errorf("parsing config file: %w", err)
        }
    }
    
    // Override with environment variables
    if dbPath := os.Getenv("DATABASE_PATH"); dbPath != "" {
        cfg.Database.Path = dbPath
    }
    
    if serverPort := os.Getenv("SERVER_PORT"); serverPort != "" {
        var port int
        if _, err := fmt.Sscanf(serverPort, "%d", &port); err == nil {
            cfg.Server.Port = port
        }
    }
    
    return &cfg, nil
}

func (c *Config) Validate() error {
    if c.Database.Path == "" {
        return fmt.Errorf("database path is required")
    }
    
    if c.Database.MaxOpenConns < 1 {
        return fmt.Errorf("max_open_conns must be at least 1")
    }
    
    if c.Database.MaxIdleConns < 0 {
        return fmt.Errorf("max_idle_conns cannot be negative")
    }
    
    if c.Server.Port < 1 || c.Server.Port > 65535 {
        return fmt.Errorf("server port must be between 1 and 65535")
    }
    
    return nil
}
```

This configuration system provides several important capabilities for production deployment. Default values ensure the application can start with minimal configuration while still providing reasonable performance characteristics. Environment variable overrides allow deployment-specific values to be injected without modifying configuration files, which is essential for containerized deployments.

The validation method ensures that critical configuration values are present and within acceptable ranges, catching configuration errors early in the application startup process. The structured approach to configuration makes it easy to add new options as the application evolves while maintaining backward compatibility.

## Database Schema Design and Migration Management

Effective schema design and migration management form the foundation of maintainable database applications. SQLite's features enable sophisticated schema designs while migration tooling ensures safe schema evolution in production environments.

### Schema Design Principles

When designing schemas for SQLite, several principles guide optimal performance and maintainability. First, leverage SQLite's flexible typing system while maintaining data integrity through constraints and foreign keys. Second, design indexes carefully since SQLite's query planner benefits from well-chosen indexes but can be hindered by excessive indexing. Third, consider SQLite-specific optimizations like the rowid column and WITHOUT ROWID tables for specific use cases.

The following migration demonstrates a foundational schema design that incorporates these principles:

```sql
-- Migration: 001_initial_schema.up.sql
PRAGMA foreign_keys = ON;

-- Users table with comprehensive indexing strategy
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL UNIQUE,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_at DATETIME
);

-- Optimize for common query patterns
CREATE INDEX idx_users_email ON users(email) WHERE is_active = TRUE;
CREATE INDEX idx_users_username ON users(username) WHERE is_active = TRUE;
CREATE INDEX idx_users_uuid ON users(uuid);
CREATE INDEX idx_users_created_at ON users(created_at);
CREATE INDEX idx_users_last_login ON users(last_login_at) WHERE last_login_at IS NOT NULL;

-- Products table with hierarchical categories
CREATE TABLE product_categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    slug TEXT NOT NULL UNIQUE,
    description TEXT,
    parent_id INTEGER,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (parent_id) REFERENCES product_categories(id) ON DELETE SET NULL
);

CREATE INDEX idx_product_categories_parent ON product_categories(parent_id);
CREATE INDEX idx_product_categories_slug ON product_categories(slug) WHERE is_active = TRUE;
CREATE INDEX idx_product_categories_sort ON product_categories(sort_order);

CREATE TABLE products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    sku TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    category_id INTEGER NOT NULL,
    price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
    cost_cents INTEGER CHECK (cost_cents >= 0),
    weight_grams INTEGER CHECK (weight_grams >= 0),
    dimensions_json TEXT, -- JSON: {"length": 10, "width": 5, "height": 3}
    stock_quantity INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    low_stock_threshold INTEGER NOT NULL DEFAULT 10,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_featured BOOLEAN NOT NULL DEFAULT FALSE,
    requires_shipping BOOLEAN NOT NULL DEFAULT TRUE,
    metadata_json TEXT, -- Flexible JSON storage for product attributes
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (category_id) REFERENCES product_categories(id) ON DELETE RESTRICT
);

-- Performance indexes for products
CREATE INDEX idx_products_category ON products(category_id) WHERE is_active = TRUE;
CREATE INDEX idx_products_sku ON products(sku);
CREATE INDEX idx_products_uuid ON products(uuid);
CREATE INDEX idx_products_price ON products(price_cents) WHERE is_active = TRUE;
CREATE INDEX idx_products_featured ON products(is_featured) WHERE is_featured = TRUE AND is_active = TRUE;
CREATE INDEX idx_products_stock ON products(stock_quantity) WHERE is_active = TRUE;
CREATE INDEX idx_products_name_fts ON products(name) WHERE is_active = TRUE;

-- Orders table with comprehensive audit trail
CREATE TABLE orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    user_id INTEGER NOT NULL,
    order_number TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL CHECK (status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded')),
    subtotal_cents INTEGER NOT NULL CHECK (subtotal_cents >= 0),
    tax_cents INTEGER NOT NULL DEFAULT 0 CHECK (tax_cents >= 0),
    shipping_cents INTEGER NOT NULL DEFAULT 0 CHECK (shipping_cents >= 0),
    discount_cents INTEGER NOT NULL DEFAULT 0 CHECK (discount_cents >= 0),
    total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
    currency_code TEXT NOT NULL DEFAULT 'USD',
    payment_method TEXT,
    payment_status TEXT NOT NULL DEFAULT 'pending' CHECK (payment_status IN ('pending', 'authorized', 'captured', 'failed', 'refunded')),
    shipping_address_json TEXT, -- JSON storage for flexibility
    billing_address_json TEXT,
    notes TEXT,
    metadata_json TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    shipped_at DATETIME,
    delivered_at DATETIME,
    
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT
);

-- Order performance indexes
CREATE INDEX idx_orders_user ON orders(user_id);
CREATE INDEX idx_orders_uuid ON orders(uuid);
CREATE INDEX idx_orders_number ON orders(order_number);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created ON orders(created_at);
CREATE INDEX idx_orders_total ON orders(total_cents);
CREATE INDEX idx_orders_user_created ON orders(user_id, created_at);

-- Order items with detailed tracking
CREATE TABLE order_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents >= 0),
    total_price_cents INTEGER NOT NULL CHECK (total_price_cents >= 0),
    product_snapshot_json TEXT NOT NULL, -- Store product details at time of order
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT,
    
    UNIQUE(order_id, product_id)
);

CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_order_items_product ON order_items(product_id);

-- Audit log for critical operations
CREATE TABLE audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name TEXT NOT NULL,
    record_id INTEGER NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    user_id INTEGER,
    old_values_json TEXT,
    new_values_json TEXT,
    changed_fields TEXT, -- Comma-separated list of changed fields
    ip_address TEXT,
    user_agent TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_audit_logs_table_record ON audit_logs(table_name, record_id);
CREATE INDEX idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_created ON audit_logs(created_at);
CREATE INDEX idx_audit_logs_operation ON audit_logs(operation);

-- Full-text search setup for products
CREATE VIRTUAL TABLE products_fts USING fts5(
    name, 
    description, 
    content=products, 
    content_rowid=id
);

-- Triggers to maintain FTS index
CREATE TRIGGER products_fts_insert AFTER INSERT ON products BEGIN
    INSERT INTO products_fts(rowid, name, description) 
    VALUES (new.id, new.name, new.description);
END;

CREATE TRIGGER products_fts_delete AFTER DELETE ON products BEGIN
    INSERT INTO products_fts(products_fts, rowid, name, description) 
    VALUES('delete', old.id, old.name, old.description);
END;

CREATE TRIGGER products_fts_update AFTER UPDATE ON products BEGIN
    INSERT INTO products_fts(products_fts, rowid, name, description) 
    VALUES('delete', old.id, old.name, old.description);
    INSERT INTO products_fts(rowid, name, description) 
    VALUES (new.id, new.name, new.description);
END;

-- Update triggers for maintaining updated_at timestamps
CREATE TRIGGER update_users_updated_at 
    AFTER UPDATE ON users
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE users SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TRIGGER update_products_updated_at 
    AFTER UPDATE ON products
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE products SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TRIGGER update_orders_updated_at 
    AFTER UPDATE ON orders
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE orders SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TRIGGER update_product_categories_updated_at 
    AFTER UPDATE ON product_categories
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE product_categories SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;
```

This schema demonstrates several important SQLite optimization techniques. The use of partial indexes with WHERE clauses reduces index size and improves performance for common query patterns. CHECK constraints ensure data integrity at the database level, preventing invalid data from entering the system. The JSON columns provide flexibility for storing semi-structured data while maintaining the benefits of SQL queries for structured fields.

The full-text search implementation using FTS5 provides powerful search capabilities without requiring external search engines. The trigger-based approach ensures the search index remains synchronized with the main table data automatically.

### Migration Management with golang-migrate

Managing schema changes in production requires a robust migration system. golang-migrate provides the necessary functionality for safe, versioned schema evolution. The following Go code demonstrates setting up and managing migrations:

```go
package database

import (
    "context"
    "database/sql"
    "fmt"
    "log"
    "path/filepath"
    
    "github.com/golang-migrate/migrate/v4"
    "github.com/golang-migrate/migrate/v4/database/sqlite3"
    "github.com/golang-migrate/migrate/v4/source/file"
    _ "github.com/mattn/go-sqlite3"
)

type MigrationManager struct {
    db          *sql.DB
    migrationsPath string
    migrate     *migrate.Migrate
}

func NewMigrationManager(db *sql.DB, migrationsPath string) (*MigrationManager, error) {
    // Create file source for migrations
    sourceURL := fmt.Sprintf("file://%s", migrationsPath)
    source, err := (&file.File{}).Open(sourceURL)
    if err != nil {
        return nil, fmt.Errorf("opening migration source: %w", err)
    }
    
    // Create database driver
    driver, err := sqlite3.WithInstance(db, &sqlite3.Config{})
    if err != nil {
        return nil, fmt.Errorf("creating database driver: %w", err)
    }
    
    // Create migrate instance
    m, err := migrate.NewWithInstance("file", source, "sqlite3", driver)
    if err != nil {
        return nil, fmt.Errorf("creating migrate instance: %w", err)
    }
    
    return &MigrationManager{
        db:          db,
        migrationsPath: migrationsPath,
        migrate:     m,
    }, nil
}

func (mm *MigrationManager) Up(ctx context.Context) error {
    return mm.migrate.Up()
}

func (mm *MigrationManager) Down(ctx context.Context) error {
    return mm.migrate.Down()
}

func (mm *MigrationManager) Migrate(ctx context.Context, version uint) error {
    return mm.migrate.Migrate(version)
}

func (mm *MigrationManager) Version() (uint, bool, error) {
    return mm.migrate.Version()
}

func (mm *MigrationManager) Steps(n int) error {
    return mm.migrate.Steps(n)
}

func (mm *MigrationManager) Close() error {
    sourceErr, dbErr := mm.migrate.Close()
    if sourceErr != nil {
        return sourceErr
    }
    return dbErr
}

// MigrationStatus provides information about migration state
type MigrationStatus struct {
    CurrentVersion uint
    IsDirty        bool
    LatestVersion  uint
    PendingCount   int
}

func (mm *MigrationManager) Status(ctx context.Context) (*MigrationStatus, error) {
    current, dirty, err := mm.migrate.Version()
    if err != nil && err != migrate.ErrNilVersion {
        return nil, fmt.Errorf("getting current version: %w", err)
    }
    
    // Find latest migration version by scanning files
    pattern := filepath.Join(mm.migrationsPath, "*.up.sql")
    files, err := filepath.Glob(pattern)
    if err != nil {
        return nil, fmt.Errorf("scanning migration files: %w", err)
    }
    
    var latest uint
    for _, file := range files {
        var version uint
        base := filepath.Base(file)
        if _, err := fmt.Sscanf(base, "%d_", &version); err == nil {
            if version > latest {
                latest = version
            }
        }
    }
    
    pending := 0
    if err != migrate.ErrNilVersion {
        if latest > current {
            pending = int(latest - current)
        }
    } else {
        pending = len(files)
        current = 0
    }
    
    return &MigrationStatus{
        CurrentVersion: current,
        IsDirty:        dirty,
        LatestVersion:  latest,
        PendingCount:   pending,
    }, nil
}

// ValidateMigration performs safety checks before applying migrations
func (mm *MigrationManager) ValidateMigration(ctx context.Context, targetVersion uint) error {
    current, dirty, err := mm.migrate.Version()
    if err != nil && err != migrate.ErrNilVersion {
        return fmt.Errorf("getting current version: %w", err)
    }
    
    if dirty {
        return fmt.Errorf("database is in dirty state, manual intervention required")
    }
    
    if err != migrate.ErrNilVersion && targetVersion < current {
        return fmt.Errorf("target version %d is less than current version %d", targetVersion, current)
    }
    
    // Additional validation could include:
    // - Checking for data conflicts
    // - Validating migration syntax
    // - Ensuring proper backup exists
    
    return nil
}

// CreateMigration helps generate new migration files
func CreateMigration(migrationsPath, name string) error {
    // Find next version number
    pattern := filepath.Join(migrationsPath, "*.up.sql")
    files, err := filepath.Glob(pattern)
    if err != nil {
        return fmt.Errorf("scanning existing migrations: %w", err)
    }
    
    var maxVersion uint
    for _, file := range files {
        var version uint
        base := filepath.Base(file)
        if _, err := fmt.Sscanf(base, "%d_", &version); err == nil {
            if version > maxVersion {
                maxVersion = version
            }
        }
    }
    
    nextVersion := maxVersion + 1
    
    // Create up migration file
    upFile := filepath.Join(migrationsPath, fmt.Sprintf("%03d_%s.up.sql", nextVersion, name))
    downFile := filepath.Join(migrationsPath, fmt.Sprintf("%03d_%s.down.sql", nextVersion, name))
    
    upContent := fmt.Sprintf("-- Migration: %03d_%s.up.sql\n-- Add your up migration here\n\n", nextVersion, name)
    downContent := fmt.Sprintf("-- Migration: %03d_%s.down.sql\n-- Add your down migration here\n\n", nextVersion, name)
    
    if err := writeFile(upFile, upContent); err != nil {
        return fmt.Errorf("creating up migration: %w", err)
    }
    
    if err := writeFile(downFile, downContent); err != nil {
        return fmt.Errorf("creating down migration: %w", err)
    }
    
    log.Printf("Created migration files:\n  %s\n  %s", upFile, downFile)
    return nil
}

func writeFile(filename, content string) error {
    file, err := os.Create(filename)
    if err != nil {
        return err
    }
    defer file.Close()
    
    _, err = file.WriteString(content)
    return err
}
```

This migration management system provides comprehensive functionality for handling schema evolution safely. The validation methods help prevent common migration mistakes like applying migrations to dirty databases or attempting to downgrade to earlier versions without proper consideration.

The status functionality provides visibility into the current migration state, which is essential for deployment automation and troubleshooting. The migration creation helper ensures consistent naming and structure for new migrations.

### Advanced Schema Patterns

SQLite supports several advanced patterns that can significantly improve application performance and maintainability. Understanding these patterns enables developers to leverage SQLite's full capabilities.

```sql
-- Migration: 002_advanced_patterns.up.sql

-- Materialized view pattern using triggers
CREATE TABLE user_order_stats (
    user_id INTEGER PRIMARY KEY,
    total_orders INTEGER NOT NULL DEFAULT 0,
    total_spent_cents INTEGER NOT NULL DEFAULT 0,
    last_order_date DATETIME,
    first_order_date DATETIME,
    average_order_value_cents INTEGER NOT NULL DEFAULT 0,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Initialize stats for existing users
INSERT INTO user_order_stats (user_id, updated_at)
SELECT id, CURRENT_TIMESTAMP FROM users;

-- Trigger to maintain user order statistics
CREATE TRIGGER update_user_order_stats_insert
    AFTER INSERT ON orders
    FOR EACH ROW
BEGIN
    INSERT OR REPLACE INTO user_order_stats (
        user_id,
        total_orders,
        total_spent_cents,
        last_order_date,
        first_order_date,
        average_order_value_cents,
        updated_at
    )
    SELECT 
        NEW.user_id,
        COUNT(*),
        SUM(total_cents),
        MAX(created_at),
        MIN(created_at),
        AVG(total_cents),
        CURRENT_TIMESTAMP
    FROM orders 
    WHERE user_id = NEW.user_id AND status NOT IN ('cancelled', 'refunded');
END;

CREATE TRIGGER update_user_order_stats_update
    AFTER UPDATE ON orders
    FOR EACH ROW
    WHEN OLD.total_cents != NEW.total_cents OR OLD.status != NEW.status
BEGIN
    INSERT OR REPLACE INTO user_order_stats (
        user_id,
        total_orders,
        total_spent_cents,
        last_order_date,
        first_order_date,
        average_order_value_cents,
        updated_at
    )
    SELECT 
        NEW.user_id,
        COUNT(*),
        SUM(total_cents),
        MAX(created_at),
        MIN(created_at),
        AVG(total_cents),
        CURRENT_TIMESTAMP
    FROM orders 
    WHERE user_id = NEW.user_id AND status NOT IN ('cancelled', 'refunded');
END;

-- Partitioning pattern using date-based tables
CREATE TABLE order_events_2025_01 (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id INTEGER NOT NULL,
    event_type TEXT NOT NULL,
    event_data_json TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
    CHECK (created_at >= '2025-01-01' AND created_at < '2025-02-01')
);

CREATE INDEX idx_order_events_2025_01_order ON order_events_2025_01(order_id);
CREATE INDEX idx_order_events_2025_01_type ON order_events_2025_01(event_type);
CREATE INDEX idx_order_events_2025_01_created ON order_events_2025_01(created_at);

-- View to union partitioned tables
CREATE VIEW order_events AS
    SELECT * FROM order_events_2025_01
    -- Add more partitions as needed
;

-- Hierarchical data pattern with recursive CTE support
CREATE TABLE categories_closure (
    ancestor_id INTEGER NOT NULL,
    descendant_id INTEGER NOT NULL,
    depth INTEGER NOT NULL,
    
    PRIMARY KEY (ancestor_id, descendant_id),
    FOREIGN KEY (ancestor_id) REFERENCES product_categories(id) ON DELETE CASCADE,
    FOREIGN KEY (descendant_id) REFERENCES product_categories(id) ON DELETE CASCADE
);

-- Initialize closure table for existing categories
WITH RECURSIVE category_paths AS (
    -- Base case: each category is its own descendant at depth 0
    SELECT id AS ancestor_id, id AS descendant_id, 0 AS depth
    FROM product_categories
    
    UNION ALL
    
    -- Recursive case: find all descendant relationships
    SELECT cp.ancestor_id, pc.id AS descendant_id, cp.depth + 1
    FROM category_paths cp
    JOIN product_categories pc ON pc.parent_id = cp.descendant_id
)
INSERT INTO categories_closure (ancestor_id, descendant_id, depth)
SELECT ancestor_id, descendant_id, depth FROM category_paths;

-- Triggers to maintain closure table
CREATE TRIGGER maintain_category_closure_insert
    AFTER INSERT ON product_categories
    FOR EACH ROW
BEGIN
    -- Insert self-reference
    INSERT INTO categories_closure (ancestor_id, descendant_id, depth)
    VALUES (NEW.id, NEW.id, 0);
    
    -- Insert relationships with all ancestors if this has a parent
    INSERT INTO categories_closure (ancestor_id, descendant_id, depth)
    SELECT ancestor_id, NEW.id, depth + 1
    FROM categories_closure
    WHERE descendant_id = NEW.parent_id AND NEW.parent_id IS NOT NULL;
END;

-- Optimized query patterns using generated columns (SQLite 3.31+)
ALTER TABLE products ADD COLUMN search_text TEXT GENERATED ALWAYS AS (
    name || ' ' || COALESCE(description, '')
) STORED;

CREATE INDEX idx_products_search_text ON products(search_text);

-- Time-series data pattern with efficient queries
CREATE TABLE product_price_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL,
    price_cents INTEGER NOT NULL,
    effective_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_date DATETIME,
    created_by INTEGER,
    reason TEXT,
    
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_price_history_product_date ON product_price_history(product_id, effective_date);
CREATE INDEX idx_price_history_effective ON product_price_history(effective_date);

-- Trigger to maintain price history
CREATE TRIGGER maintain_price_history
    AFTER UPDATE OF price_cents ON products
    FOR EACH ROW
    WHEN OLD.price_cents != NEW.price_cents
BEGIN
    -- Close previous price record
    UPDATE product_price_history 
    SET end_date = CURRENT_TIMESTAMP
    WHERE product_id = NEW.id AND end_date IS NULL;
    
    -- Insert new price record
    INSERT INTO product_price_history (product_id, price_cents, effective_date)
    VALUES (NEW.id, NEW.price_cents, CURRENT_TIMESTAMP);
END;
```

These advanced patterns demonstrate SQLite's capability to handle complex data relationships and maintain derived data efficiently. The materialized view pattern using triggers provides real-time aggregation without the overhead of computing statistics on each query. The closure table pattern enables efficient hierarchical queries without recursive CTEs at query time, improving performance for complex category structures.

The partitioning pattern shows how to manage large time-series data by splitting it across multiple tables while maintaining a unified view. This approach can significantly improve query performance for date-range queries and simplifies data archival processes.

## sqlc Configuration and Code Generation

sqlc transforms the database development experience by generating type-safe Go code from SQL queries. Proper configuration ensures optimal code generation while maintaining flexibility for complex query patterns.

### Comprehensive sqlc Configuration

The sqlc configuration file controls all aspects of code generation, from basic type mappings to advanced overrides for complex scenarios:

```yaml
version: "2"
cloud:
  # Optional: sqlc Cloud configuration for team collaboration
  # project: "your-project-id"
  # auth_token: "${SQLC_AUTH_TOKEN}"

sql:
  - engine: "sqlite"
    queries: "internal/database/queries"
    schema: "internal/database/migrations"
    gen:
      go:
        package: "sqlc"
        out: "internal/database/sqlc"
        sql_package: "database/sql"
        emit_interface: true
        emit_json_tags: true
        emit_db_tags: true
        emit_prepared_queries: true
        emit_exact_table_names: false
        emit_empty_slices: true
        emit_exported_queries: true
        emit_result_struct_pointers: false
        emit_params_struct_pointers: false
        emit_methods_with_db_argument: false
        emit_pointers_for_null_types: true
        emit_enum_valid_method: true
        emit_all_enum_values: true
        json_tags_case_style: "snake"
        omit_unused_structs: true
        omit_sqlc_version: false
        query_parameter_limit: 32767
        batch_size: 1000
        
        # Type overrides for better Go integration
        overrides:
          - column: "*.uuid"
            go_type: "github.com/google/uuid.UUID"
          - column: "*.created_at"
            go_type: "time.Time"
          - column: "*.updated_at"
            go_type: "time.Time"
          - column: "*.deleted_at"
            go_type: "*time.Time"
          - column: "*.last_login_at"
            go_type: "*time.Time"
          - column: "*.shipped_at"
            go_type: "*time.Time"
          - column: "*.delivered_at"
            go_type: "*time.Time"
          - column: "*_json"
            go_type: "json.RawMessage"
          - column: "*.is_active"
            go_type: "bool"
          - column: "*.is_featured"
            go_type: "bool"
          - column: "*.email_verified"
            go_type: "bool"
          - column: "*.requires_shipping"
            go_type: "bool"
          - column: "*.wal_mode"
            go_type: "bool"
          - column: "*_cents"
            go_type: "int64"
          - column: "*.price_cents"
            go_type: "int64"
          - column: "*.total_cents"
            go_type: "int64"
          - column: "users.email"
            go_type: "string"
            go_struct_tag: 'json:"email" db:"email" validate:"required,email"'
          - column: "users.password_hash"
            go_type: "string"
            go_struct_tag: 'json:"-" db:"password_hash"'
            
        # Custom type mappings for enums
        rename:
          order_status: "OrderStatus"
          payment_status: "PaymentStatus"
          log_level: "LogLevel"
          
        # Initialization for custom types
        initialisms:
          - "API"
          - "HTTP"
          - "JSON"
          - "UUID"
          - "URL"
          - "CSV"
          - "SQL"
          - "FTS"
          - "WAL"

rules:
  - sqlc/db-prepare
  
plugins:
  - name: "go"
    process:
      cmd: "sqlc-gen-go"
    wasm:
      url: "https://downloads.sqlc.dev/plugin/sqlc-gen-go_1.24.0.wasm"
      sha256: "sha256-of-the-wasm-file"
```

This configuration demonstrates advanced sqlc features that significantly improve the generated code quality. The type overrides ensure that UUID columns generate proper UUID types rather than strings, timestamp columns use time.Time types, and JSON columns use json.RawMessage for efficient handling.

The struct tag customization enables integration with popular Go libraries like validator for input validation and proper JSON serialization behavior. The initialization settings ensure consistent naming conventions that match Go idioms.

### Query Organization Strategy

Organizing SQL queries effectively improves maintainability and enables better code generation. The strategy involves grouping related queries by domain entity while maintaining clear separation of concerns:

```sql
-- internal/database/queries/users.sql

-- name: CreateUser :one
INSERT INTO users (
    uuid,
    email,
    username,
    password_hash,
    first_name,
    last_name,
    is_active,
    email_verified
) VALUES (
    ?, ?, ?, ?, ?, ?, ?, ?
) RETURNING *;

-- name: GetUserByID :one
SELECT * FROM users
WHERE id = ? AND is_active = TRUE;

-- name: GetUserByUUID :one
SELECT * FROM users
WHERE uuid = ? AND is_active = TRUE;

-- name: GetUserByEmail :one
SELECT * FROM users
WHERE email = ? AND is_active = TRUE;

-- name: GetUserByUsername :one
SELECT * FROM users
WHERE username = ? AND is_active = TRUE;

-- name: UpdateUser :one
UPDATE users SET
    email = COALESCE(sqlc.narg('email'), email),
    username = COALESCE(sqlc.narg('username'), username),
    first_name = COALESCE(sqlc.narg('first_name'), first_name),
    last_name = COALESCE(sqlc.narg('last_name'), last_name),
    email_verified = COALESCE(sqlc.narg('email_verified'), email_verified),
    updated_at = CURRENT_TIMESTAMP
WHERE id = sqlc.arg('id') AND is_active = TRUE
RETURNING *;

-- name: UpdateUserPassword :exec
UPDATE users SET
    password_hash = ?,
    updated_at = CURRENT_TIMESTAMP
WHERE id = ?;

-- name: UpdateUserLastLogin :exec
UPDATE users SET
    last_login_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE id = ?;

-- name: DeactivateUser :exec
UPDATE users SET
    is_active = FALSE,
    updated_at = CURRENT_TIMESTAMP
WHERE id = ?;

-- name: ListUsers :many
SELECT 
    id,
    uuid,
    email,
    username,
    first_name,
    last_name,
    is_active,
    email_verified,
    created_at,
    updated_at,
    last_login_at
FROM users
WHERE 
    is_active = TRUE
    AND (sqlc.narg('search') IS NULL OR (
        email LIKE '%' || sqlc.narg('search') || '%' OR
        username LIKE '%' || sqlc.narg('search') || '%' OR
        first_name LIKE '%' || sqlc.narg('search') || '%' OR
        last_name LIKE '%' || sqlc.narg('search') || '%'
    ))
ORDER BY 
    CASE WHEN sqlc.narg('sort_by') = 'email' THEN email END ASC,
    CASE WHEN sqlc.narg('sort_by') = 'username' THEN username END ASC,
    CASE WHEN sqlc.narg('sort_by') = 'created_at' THEN created_at END DESC,
    id ASC
LIMIT sqlc.narg('limit') OFFSET sqlc.narg('offset');

-- name: CountUsers :one
SELECT COUNT(*) FROM users
WHERE 
    is_active = TRUE
    AND (sqlc.narg('search') IS NULL OR (
        email LIKE '%' || sqlc.narg('search') || '%' OR
        username LIKE '%' || sqlc.narg('search') || '%' OR
        first_name LIKE '%' || sqlc.narg('search') || '%' OR
        last_name LIKE '%' || sqlc.narg('search') || '%'
    ));

-- name: GetUserStats :one
SELECT 
    u.id,
    u.uuid,
    u.email,
    u.username,
    u.first_name,
    u.last_name,
    u.created_at,
    COALESCE(uos.total_orders, 0) as total_orders,
    COALESCE(uos.total_spent_cents, 0) as total_spent_cents,
    uos.last_order_date,
    uos.first_order_date,
    COALESCE(uos.average_order_value_cents, 0) as average_order_value_cents
FROM users u
LEFT JOIN user_order_stats uos ON u.id = uos.user_id
WHERE u.id = ? AND u.is_active = TRUE;

-- name: BatchCreateUsers :copyfrom
INSERT INTO users (
    uuid,
    email,
    username,
    password_hash,
    first_name,
    last_name,
    is_active,
    email_verified
) VALUES (
    ?, ?, ?, ?, ?, ?, ?, ?
);
```

This query organization demonstrates several important patterns for effective sqlc usage. The use of `sqlc.narg()` for optional parameters enables flexible query building without complex dynamic SQL construction. The combination of search and pagination parameters in the list queries provides efficient data access patterns commonly needed in web applications.

The batch insert query using `:copyfrom` leverages PostgreSQL's COPY protocol for efficient bulk operations, though this specific syntax is PostgreSQL-specific and would need adaptation for SQLite.

### Complex Query Patterns

Advanced applications often require complex queries that test the limits of sqlc's code generation capabilities. Understanding how to structure these queries ensures optimal generated code:

```sql
-- internal/database/queries/orders.sql

-- name: CreateOrder :one
INSERT INTO orders (
    uuid,
    user_id,
    order_number,
    status,
    subtotal_cents,
    tax_cents,
    shipping_cents,
    discount_cents,
    total_cents,
    currency_code,
    payment_method,
    payment_status,
    shipping_address_json,
    billing_address_json,
    notes,
    metadata_json
) VALUES (
    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
) RETURNING *;

-- name: GetOrderWithItems :one
SELECT 
    sqlc.embed(orders),
    sqlc.embed(users)
FROM orders
JOIN users ON orders.user_id = users.id
WHERE orders.uuid = ? AND orders.user_id = ?;

-- name: GetOrderItems :many
SELECT 
    oi.*,
    p.name as product_name,
    p.sku as product_sku,
    p.is_active as product_is_active
FROM order_items oi
JOIN products p ON oi.product_id = p.id
WHERE oi.order_id = ?
ORDER BY oi.id;

-- name: UpdateOrderStatus :one
UPDATE orders SET
    status = ?,
    updated_at = CURRENT_TIMESTAMP,
    shipped_at = CASE WHEN ? = 'shipped' THEN CURRENT_TIMESTAMP ELSE shipped_at END,
    delivered_at = CASE WHEN ? = 'delivered' THEN CURRENT_TIMESTAMP ELSE delivered_at END
WHERE uuid = ? AND user_id = ?
RETURNING *;

-- name: GetOrderAnalytics :one
WITH order_metrics AS (
    SELECT 
        COUNT(*) as total_orders,
        SUM(total_cents) as total_revenue_cents,
        AVG(total_cents) as average_order_value_cents,
        MIN(total_cents) as min_order_value_cents,
        MAX(total_cents) as max_order_value_cents,
        COUNT(DISTINCT user_id) as unique_customers
    FROM orders
    WHERE 
        created_at >= ? 
        AND created_at <= ?
        AND status NOT IN ('cancelled', 'refunded')
),
daily_orders AS (
    SELECT 
        DATE(created_at) as order_date,
        COUNT(*) as daily_count,
        SUM(total_cents) as daily_revenue_cents
    FROM orders
    WHERE 
        created_at >= ? 
        AND created_at <= ?
        AND status NOT IN ('cancelled', 'refunded')
    GROUP BY DATE(created_at)
),
status_breakdown AS (
    SELECT 
        status,
        COUNT(*) as status_count,
        SUM(total_cents) as status_revenue_cents
    FROM orders
    WHERE 
        created_at >= ? 
        AND created_at <= ?
    GROUP BY status
)
SELECT 
    om.total_orders,
    om.total_revenue_cents,
    om.average_order_value_cents,
    om.min_order_value_cents,
    om.max_order_value_cents,
    om.unique_customers,
    COUNT(do.order_date) as active_days,
    AVG(do.daily_count) as avg_orders_per_day,
    AVG(do.daily_revenue_cents) as avg_revenue_per_day,
    json_group_object(sb.status, json_object(
        'count', sb.status_count,
        'revenue_cents', sb.status_revenue_cents
    )) as status_breakdown_json
FROM order_metrics om
CROSS JOIN daily_orders do
CROSS JOIN status_breakdown sb
GROUP BY om.total_orders, om.total_revenue_cents, om.average_order_value_cents, 
         om.min_order_value_cents, om.max_order_value_cents, om.unique_customers;

-- name: SearchOrders :many
SELECT 
    o.*,
    u.email as user_email,
    u.username as user_username,
    u.first_name as user_first_name,
    u.last_name as user_last_name
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE 
    (sqlc.narg('user_id') IS NULL OR o.user_id = sqlc.narg('user_id'))
    AND (sqlc.narg('status') IS NULL OR o.status = sqlc.narg('status'))
    AND (sqlc.narg('payment_status') IS NULL OR o.payment_status = sqlc.narg('payment_status'))
    AND (sqlc.narg('start_date') IS NULL OR o.created_at >= sqlc.narg('start_date'))
    AND (sqlc.narg('end_date') IS NULL OR o.created_at <= sqlc.narg('end_date'))
    AND (sqlc.narg('min_total') IS NULL OR o.total_cents >= sqlc.narg('min_total'))
    AND (sqlc.narg('max_total') IS NULL OR o.total_cents <= sqlc.narg('max_total'))
    AND (sqlc.narg('search') IS NULL OR (
        o.order_number LIKE '%' || sqlc.narg('search') || '%' OR
        u.email LIKE '%' || sqlc.narg('search') || '%' OR
        u.username LIKE '%' || sqlc.narg('search') || '%'
    ))
ORDER BY 
    CASE WHEN sqlc.narg('sort_by') = 'created_at' AND sqlc.narg('sort_desc') = TRUE THEN o.created_at END DESC,
    CASE WHEN sqlc.narg('sort_by') = 'created_at' AND sqlc.narg('sort_desc') = FALSE THEN o.created_at END ASC,
    CASE WHEN sqlc.narg('sort_by') = 'total' AND sqlc.narg('sort_desc') = TRUE THEN o.total_cents END DESC,
    CASE WHEN sqlc.narg('sort_by') = 'total' AND sqlc.narg('sort_desc') = FALSE THEN o.total_cents END ASC,
    CASE WHEN sqlc.narg('sort_by') = 'order_number' THEN o.order_number END ASC,
    o.created_at DESC
LIMIT sqlc.narg('limit') OFFSET sqlc.narg('offset');

-- name: GetTopCustomers :many
SELECT 
    u.id,
    u.uuid,
    u.email,
    u.username,
    u.first_name,
    u.last_name,
    COUNT(o.id) as total_orders,
    SUM(o.total_cents) as total_spent_cents,
    AVG(o.total_cents) as average_order_value_cents,
    MAX(o.created_at) as last_order_date,
    MIN(o.created_at) as first_order_date
FROM users u
JOIN orders o ON u.id = o.user_id
WHERE 
    o.status NOT IN ('cancelled', 'refunded')
    AND o.created_at >= ?
    AND o.created_at <= ?
GROUP BY u.id, u.uuid, u.email, u.username, u.first_name, u.last_name
HAVING COUNT(o.id) >= ?
ORDER BY total_spent_cents DESC
LIMIT ?;

-- name: CreateOrderWithItems :exec
WITH new_order AS (
    INSERT INTO orders (
        uuid, user_id, order_number, status, subtotal_cents,
        tax_cents, shipping_cents, discount_cents, total_cents,
        currency_code, payment_method, payment_status,
        shipping_address_json, billing_address_json, notes, metadata_json
    ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
    ) RETURNING id
)
INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents, total_price_cents, product_snapshot_json)
SELECT 
    new_order.id,
    ?,
    ?,
    ?,
    ?,
    ?
FROM new_order;
```

These complex queries showcase sqlc's ability to handle sophisticated SQL patterns while generating clean Go code. The use of `sqlc.embed()` creates nested structs that represent joined table data efficiently. The analytics query demonstrates how CTEs can be used to build complex aggregations while maintaining readability.

The flexible search query pattern using `sqlc.narg()` for optional parameters enables building powerful search interfaces without resorting to dynamic SQL generation. The conditional ordering logic provides flexible sorting capabilities that remain type-safe at compile time.

## Generated Code Deep Dive

Understanding the code that sqlc generates enables developers to write more effective queries and leverage the generated interfaces properly. The generated code follows consistent patterns that integrate seamlessly with standard Go database practices.

### Generated Models and Types

sqlc generates Go structs that correspond to database tables and query results. The generated models include proper type mapping, JSON tags, and validation tags based on the configuration:

```go
// Code generated by sqlc. DO NOT EDIT.
// versions:
//   sqlc v1.24.0

package sqlc

import (
    "database/sql"
    "encoding/json"
    "time"
    
    "github.com/google/uuid"
)

type OrderStatus string

const (
    OrderStatusPending    OrderStatus = "pending"
    OrderStatusConfirmed  OrderStatus = "confirmed"
    OrderStatusProcessing OrderStatus = "processing"
    OrderStatusShipped    OrderStatus = "shipped"
    OrderStatusDelivered  OrderStatus = "delivered"
    OrderStatusCancelled  OrderStatus = "cancelled"
    OrderStatusRefunded   OrderStatus = "refunded"
)

func (e *OrderStatus) Scan(src interface{}) error {
    switch s := src.(type) {
    case string:
        *e = OrderStatus(s)
    case []byte:
        *e = OrderStatus(s)
    default:
        return fmt.Errorf("unsupported Scan, storing driver.Value type %T into type %T", src, e)
    }
    return nil
}

func (e OrderStatus) Value() (driver.Value, error) {
    return string(e), nil
}

func (e OrderStatus) Valid() bool {
    switch e {
    case OrderStatusPending, OrderStatusConfirmed, OrderStatusProcessing,
         OrderStatusShipped, OrderStatusDelivered, OrderStatusCancelled, OrderStatusRefunded:
        return true
    }
    return false
}

type PaymentStatus string

const (
    PaymentStatusPending    PaymentStatus = "pending"
    PaymentStatusAuthorized PaymentStatus = "authorized"
    PaymentStatusCaptured   PaymentStatus = "captured"
    PaymentStatusFailed     PaymentStatus = "failed"
    PaymentStatusRefunded   PaymentStatus = "refunded"
)

func (e *PaymentStatus) Scan(src interface{}) error {
    switch s := src.(type) {
    case string:
        *e = PaymentStatus(s)
    case []byte:
        *e = PaymentStatus(s)
    default:
        return fmt.Errorf("unsupported Scan, storing driver.Value type %T into type %T", src, e)
    }
    return nil
}

func (e PaymentStatus) Value() (driver.Value, error) {
    return string(e), nil
}

func (e PaymentStatus) Valid() bool {
    switch e {
    case PaymentStatusPending, PaymentStatusAuthorized, PaymentStatusCaptured,
         PaymentStatusFailed, PaymentStatusRefunded:
        return true
    }
    return false
}

type User struct {
    ID             int64      `json:"id" db:"id"`
    UUID           uuid.UUID  `json:"uuid" db:"uuid"`
    Email          string     `json:"email" db:"email" validate:"required,email"`
    Username       string     `json:"username" db:"username"`
    PasswordHash   string     `json:"-" db:"password_hash"`
    FirstName      string     `json:"first_name" db:"first_name"`
    LastName       string     `json:"last_name" db:"last_name"`
    IsActive       bool       `json:"is_active" db:"is_active"`
    EmailVerified  bool       `json:"email_verified" db:"email_verified"`
    CreatedAt      time.Time  `json:"created_at" db:"created_at"`
    UpdatedAt      time.Time  `json:"updated_at" db:"updated_at"`
    LastLoginAt    *time.Time `json:"last_login_at" db:"last_login_at"`
}

type ProductCategory struct {
    ID          int64     `json:"id" db:"id"`
    Name        string    `json:"name" db:"name"`
    Slug        string    `json:"slug" db:"slug"`
    Description *string   `json:"description" db:"description"`
    ParentID    *int64    `json:"parent_id" db:"parent_id"`
    SortOrder   int64     `json:"sort_order" db:"sort_order"`
    IsActive    bool      `json:"is_active" db:"is_active"`
    CreatedAt   time.Time `json:"created_at" db:"created_at"`
    UpdatedAt   time.Time `json:"updated_at" db:"updated_at"`
}

type Product struct {
    ID                 int64           `json:"id" db:"id"`
    UUID               uuid.UUID       `json:"uuid" db:"uuid"`
    Sku                string          `json:"sku" db:"sku"`
    Name               string          `json:"name" db:"name"`
    Description        *string         `json:"description" db:"description"`
    CategoryID         int64           `json:"category_id" db:"category_id"`
    PriceCents         int64           `json:"price_cents" db:"price_cents"`
    CostCents          *int64          `json:"cost_cents" db:"cost_cents"`
    WeightGrams        *int64          `json:"weight_grams" db:"weight_grams"`
    DimensionsJson     *json.RawMessage `json:"dimensions_json" db:"dimensions_json"`
    StockQuantity      int64           `json:"stock_quantity" db:"stock_quantity"`
    LowStockThreshold  int64           `json:"low_stock_threshold" db:"low_stock_threshold"`
    IsActive           bool            `json:"is_active" db:"is_active"`
    IsFeatured         bool            `json:"is_featured" db:"is_featured"`
    RequiresShipping   bool            `json:"requires_shipping" db:"requires_shipping"`
    MetadataJson       *json.RawMessage `json:"metadata_json" db:"metadata_json"`
    CreatedAt          time.Time       `json:"created_at" db:"created_at"`
    UpdatedAt          time.Time       `json:"updated_at" db:"updated_at"`
    SearchText         *string         `json:"search_text" db:"search_text"`
}

type Order struct {
    ID                   int64            `json:"id" db:"id"`
    UUID                 uuid.UUID        `json:"uuid" db:"uuid"`
    UserID               int64            `json:"user_id" db:"user_id"`
    OrderNumber          string           `json:"order_number" db:"order_number"`
    Status               OrderStatus      `json:"status" db:"status"`
    SubtotalCents        int64            `json:"subtotal_cents" db:"subtotal_cents"`
    TaxCents             int64            `json:"tax_cents" db:"tax_cents"`
    ShippingCents        int64            `json:"shipping_cents" db:"shipping_cents"`
    DiscountCents        int64            `json:"discount_cents" db:"discount_cents"`
    TotalCents           int64            `json:"total_cents" db:"total_cents"`
    CurrencyCode         string           `json:"currency_code" db:"currency_code"`
    PaymentMethod        *string          `json:"payment_method" db:"payment_method"`
    PaymentStatus        PaymentStatus    `json:"payment_status" db:"payment_status"`
    ShippingAddressJson  *json.RawMessage `json:"shipping_address_json" db:"shipping_address_json"`
    BillingAddressJson   *json.RawMessage `json:"billing_address_json" db:"billing_address_json"`
    Notes                *string          `json:"notes" db:"notes"`
    MetadataJson         *json.RawMessage `json:"metadata_json" db:"metadata_json"`
    CreatedAt            time.Time        `json:"created_at" db:"created_at"`
    UpdatedAt            time.Time        `json:"updated_at" db:"updated_at"`
    ShippedAt            *time.Time       `json:"shipped_at" db:"shipped_at"`
    DeliveredAt          *time.Time       `json:"delivered_at" db:"delivered_at"`
}

type OrderItem struct {
    ID                   int64            `json:"id" db:"id"`
    OrderID              int64            `json:"order_id" db:"order_id"`
    ProductID            int64            `json:"product_id" db:"product_id"`
    Quantity             int64            `json:"quantity" db:"quantity"`
    UnitPriceCents       int64            `json:"unit_price_cents" db:"unit_price_cents"`
    TotalPriceCents      int64            `json:"total_price_cents" db:"total_price_cents"`
    ProductSnapshotJson  json.RawMessage  `json:"product_snapshot_json" db:"product_snapshot_json"`
    CreatedAt            time.Time        `json:"created_at" db:"created_at"`
}

// Complex query result types
type GetOrderWithItemsRow struct {
    Order Order `json:"order"`
    User  User  `json:"user"`
}

type GetOrderAnalyticsRow struct {
    TotalOrders              int64            `json:"total_orders" db:"total_orders"`
    TotalRevenueCents        int64            `json:"total_revenue_cents" db:"total_revenue_cents"`
    AverageOrderValueCents   int64            `json:"average_order_value_cents" db:"average_order_value_cents"`
    MinOrderValueCents       int64            `json:"min_order_value_cents" db:"min_order_value_cents"`
    MaxOrderValueCents       int64            `json:"max_order_value_cents" db:"max_order_value_cents"`
    UniqueCustomers          int64            `json:"unique_customers" db:"unique_customers"`
    ActiveDays               int64            `json:"active_days" db:"active_days"`
    AvgOrdersPerDay          float64          `json:"avg_orders_per_day" db:"avg_orders_per_day"`
    AvgRevenuePerDay         float64          `json:"avg_revenue_per_day" db:"avg_revenue_per_day"`
    StatusBreakdownJson      json.RawMessage  `json:"status_breakdown_json" db:"status_breakdown_json"`
}

type SearchOrdersRow struct {
    Order        Order   `json:"order"`
    UserEmail    string  `json:"user_email" db:"user_email"`
    UserUsername string  `json:"user_username" db:"user_username"`
    UserFirstName string `json:"user_first_name" db:"user_first_name"`
    UserLastName string  `json:"user_last_name" db:"user_last_name"`
}

type GetTopCustomersRow struct {
    ID                     int64     `json:"id" db:"id"`
    UUID                   uuid.UUID `json:"uuid" db:"uuid"`
    Email                  string    `json:"email" db:"email"`
    Username               string    `json:"username" db:"username"`
    FirstName              string    `json:"first_name" db:"first_name"`
    LastName               string    `json:"last_name" db:"last_name"`
    TotalOrders            int64     `json:"total_orders" db:"total_orders"`
    TotalSpentCents        int64     `json:"total_spent_cents" db:"total_spent_cents"`
    AverageOrderValueCents int64     `json:"average_order_value_cents" db:"average_order_value_cents"`
    LastOrderDate          time.Time `json:"last_order_date" db:"last_order_date"`
    FirstOrderDate         time.Time `json:"first_order_date" db:"first_order_date"`
}
```

The generated types demonstrate several important features. Enum types include validation methods that enable type-safe enum handling while maintaining database compatibility through the Scan and Value methods. The struct tags provide comprehensive metadata for JSON serialization, database mapping, and validation.

Complex query result types are automatically generated for queries that return columns from multiple tables or computed values. This approach eliminates the need for manual result mapping while maintaining type safety throughout the application.

### Generated Query Methods

sqlc generates methods that provide type-safe access to database operations. Each query method includes proper parameter binding and result scanning:

```go
// Code generated by sqlc. DO NOT EDIT.

package sqlc

import (
    "context"
    "database/sql"
    "fmt"
    "time"
    
    "github.com/google/uuid"
)

type DBTX interface {
    ExecContext(context.Context, string, ...interface{}) (sql.Result, error)
    PrepareContext(context.Context, string) (*sql.Stmt, error)
    QueryContext(context.Context, string, ...interface{}) (*sql.Rows, error)
    QueryRowContext(context.Context, string, ...interface{}) *sql.Row
}

func New(db DBTX) *Queries {
    return &Queries{db: db}
}

type Queries struct {
    db DBTX
}

func (q *Queries) WithTx(tx *sql.Tx) *Queries {
    return &Queries{
        db: tx,
    }
}

const createUser = `-- name: CreateUser :one
INSERT INTO users (
    uuid,
    email,
    username,
    password_hash,
    first_name,
    last_name,
    is_active,
    email_verified
) VALUES (
    ?, ?, ?, ?, ?, ?, ?, ?
) RETURNING id, uuid, email, username, password_hash, first_name, last_name, is_active, email_verified, created_at, updated_at, last_login_at
`

type CreateUserParams struct {
    UUID          uuid.UUID `json:"uuid"`
    Email         string    `json:"email"`
    Username      string    `json:"username"`
    PasswordHash  string    `json:"password_hash"`
    FirstName     string    `json:"first_name"`
    LastName      string    `json:"last_name"`
    IsActive      bool      `json:"is_active"`
    EmailVerified bool      `json:"email_verified"`
}

func (q *Queries) CreateUser(ctx context.Context, arg CreateUserParams) (User, error) {
    row := q.db.QueryRowContext(ctx, createUser,
        arg.UUID,
        arg.Email,
        arg.Username,
        arg.PasswordHash,
        arg.FirstName,
        arg.LastName,
        arg.IsActive,
        arg.EmailVerified,
    )
    var i User
    err := row.Scan(
        &i.ID,
        &i.UUID,
        &i.Email,
        &i.Username,
        &i.PasswordHash,
        &i.FirstName,
        &i.LastName,
        &i.IsActive,
        &i.EmailVerified,
        &i.CreatedAt,
        &i.UpdatedAt,
        &i.LastLoginAt,
    )
    return i, err
}

const getUserByID = `-- name: GetUserByID :one
SELECT id, uuid, email, username, password_hash, first_name, last_name, is_active, email_verified, created_at, updated_at, last_login_at FROM users
WHERE id = ? AND is_active = TRUE
`

func (q *Queries) GetUserByID(ctx context.Context, id int64) (User, error) {
    row := q.db.QueryRowContext(ctx, getUserByID, id)
    var i User
    err := row.Scan(
        &i.ID,
        &i.UUID,
        &i.Email,
        &i.Username,
        &i.PasswordHash,
        &i.FirstName,
        &i.LastName,
        &i.IsActive,
        &i.EmailVerified,
        &i.CreatedAt,
        &i.UpdatedAt,
        &i.LastLoginAt,
    )
    return i, err
}

const updateUser = `-- name: UpdateUser :one
UPDATE users SET
    email = COALESCE(?, email),
    username = COALESCE(?, username),
    first_name = COALESCE(?, first_name),
    last_name = COALESCE(?, last_name),
    email_verified = COALESCE(?, email_verified),
    updated_at = CURRENT_TIMESTAMP
WHERE id = ? AND is_active = TRUE
RETURNING id, uuid, email, username, password_hash, first_name, last_name, is_active, email_verified, created_at, updated_at, last_login_at
`

type UpdateUserParams struct {
    Email         *string `json:"email"`
    Username      *string `json:"username"`
    FirstName     *string `json:"first_name"`
    LastName      *string `json:"last_name"`
    EmailVerified *bool   `json:"email_verified"`
    ID            int64   `json:"id"`
}

func (q *Queries) UpdateUser(ctx context.Context, arg UpdateUserParams) (User, error) {
    row := q.db.QueryRowContext(ctx, updateUser,
        arg.Email,
        arg.Username,
        arg.FirstName,
        arg.LastName,
        arg.EmailVerified,
        arg.ID,
    )
    var i User
    err := row.Scan(
        &i.ID,
        &i.UUID,
        &i.Email,
        &i.Username,
        &i.PasswordHash,
        &i.FirstName,
        &i.LastName,
        &i.IsActive,
        &i.EmailVerified,
        &i.CreatedAt,
        &i.UpdatedAt,
        &i.LastLoginAt,
    )
    return i, err
}

const listUsers = `-- name: ListUsers :many
SELECT 
    id,
    uuid,
    email,
    username,
    first_name,
    last_name,
    is_active,
    email_verified,
    created_at,
    updated_at,
    last_login_at
FROM users
WHERE 
    is_active = TRUE
    AND (? IS NULL OR (
        email LIKE '%' || ? || '%' OR
        username LIKE '%' || ? || '%' OR
        first_name LIKE '%' || ? || '%' OR
        last_name LIKE '%' || ? || '%'
    ))
ORDER BY 
    CASE WHEN ? = 'email' THEN email END ASC,
    CASE WHEN ? = 'username' THEN username END ASC,
    CASE WHEN ? = 'created_at' THEN created_at END DESC,
    id ASC
LIMIT ? OFFSET ?
`

type ListUsersParams struct {
    Search  *string `json:"search"`
    Search2 *string `json:"search_2"`
    Search3 *string `json:"search_3"`
    Search4 *string `json:"search_4"`
    Search5 *string `json:"search_5"`
    SortBy  *string `json:"sort_by"`
    SortBy2 *string `json:"sort_by_2"`
    SortBy3 *string `json:"sort_by_3"`
    Limit   *int64  `json:"limit"`
    Offset  *int64  `json:"offset"`
}

func (q *Queries) ListUsers(ctx context.Context, arg ListUsersParams) ([]User, error) {
    rows, err := q.db.QueryContext(ctx, listUsers,
        arg.Search,
        arg.Search2,
        arg.Search3,
        arg.Search4,
        arg.Search5,
        arg.SortBy,
        arg.SortBy2,
        arg.SortBy3,
        arg.Limit,
        arg.Offset,
    )
    if err != nil {
        return nil, err
    }
    defer rows.Close()
    var items []User
    for rows.Next() {
        var i User
        if err := rows.Scan(
            &i.ID,
            &i.UUID,
            &i.Email,
            &i.Username,
            &i.FirstName,
            &i.LastName,
            &i.IsActive,
            &i.EmailVerified,
            &i.CreatedAt,
            &i.UpdatedAt,
            &i.LastLoginAt,
        ); err != nil {
            return nil, err
        }
        items = append(items, i)
    }
    if err := rows.Err(); err != nil {
        return nil, err
    }
    return items, nil
}

const getOrderAnalytics = `-- name: GetOrderAnalytics :one
WITH order_metrics AS (
    SELECT 
        COUNT(*) as total_orders,
        SUM(total_cents) as total_revenue_cents,
        AVG(total_cents) as average_order_value_cents,
        MIN(total_cents) as min_order_value_cents,
        MAX(total_cents) as max_order_value_cents,
        COUNT(DISTINCT user_id) as unique_customers
    FROM orders
    WHERE 
        created_at >= ? 
        AND created_at <= ?
        AND status NOT IN ('cancelled', 'refunded')
),
daily_orders AS (
    SELECT 
        DATE(created_at) as order_date,
        COUNT(*) as daily_count,
        SUM(total_cents) as daily_revenue_cents
    FROM orders
    WHERE 
        created_at >= ? 
        AND created_at <= ?
        AND status NOT IN ('cancelled', 'refunded')
    GROUP BY DATE(created_at)
),
status_breakdown AS (
    SELECT 
        status,
        COUNT(*) as status_count,
        SUM(total_cents) as status_revenue_cents
    FROM orders
    WHERE 
        created_at >= ? 
        AND created_at <= ?
    GROUP BY status
)
SELECT 
    om.total_orders,
    om.total_revenue_cents,
    om.average_order_value_cents,
    om.min_order_value_cents,
    om.max_order_value_cents,
    om.unique_customers,
    COUNT(do.order_date) as active_days,
    AVG(do.daily_count) as avg_orders_per_day,
    AVG(do.daily_revenue_cents) as avg_revenue_per_day,
    json_group_object(sb.status, json_object(
        'count', sb.status_count,
        'revenue_cents', sb.status_revenue_cents
    )) as status_breakdown_json
FROM order_metrics om
CROSS JOIN daily_orders do
CROSS JOIN status_breakdown sb
GROUP BY om.total_orders, om.total_revenue_cents, om.average_order_value_cents, 
         om.min_order_value_cents, om.max_order_value_cents, om.unique_customers
`

type GetOrderAnalyticsParams struct {
    StartDate  time.Time `json:"start_date"`
    EndDate    time.Time `json:"end_date"`
    StartDate2 time.Time `json:"start_date_2"`
    EndDate2   time.Time `json:"end_date_2"`
    StartDate3 time.Time `json:"start_date_3"`
    EndDate3   time.Time `json:"end_date_3"`
}

func (q *Queries) GetOrderAnalytics(ctx context.Context, arg GetOrderAnalyticsParams) (GetOrderAnalyticsRow, error) {
    row := q.db.QueryRowContext(ctx, getOrderAnalytics,
        arg.StartDate,
        arg.EndDate,
        arg.StartDate2,
        arg.EndDate2,
        arg.StartDate3,
        arg.EndDate3,
    )
    var i GetOrderAnalyticsRow
    err := row.Scan(
        &i.TotalOrders,
        &i.TotalRevenueCents,
        &i.AverageOrderValueCents,
        &i.MinOrderValueCents,
        &i.MaxOrderValueCents,
        &i.UniqueCustomers,
        &i.ActiveDays,
        &i.AvgOrdersPerDay,
        &i.AvgRevenuePerDay,
        &i.StatusBreakdownJson,
    )
    return i, err
}
```

The generated query methods demonstrate sqlc's strength in providing type-safe database access. Parameter structs ensure that all required arguments are provided while maintaining clear documentation of what each query expects. The context-aware methods enable proper cancellation and timeout handling throughout the data layer.

The DBTX interface enables the same query methods to work with both regular database connections and transactions, providing flexibility in how queries are executed. This design enables repository implementations to abstract transaction handling from service layer code.

### Working with Generated Code

Understanding how to effectively use the generated code requires attention to several key patterns. The generated types and methods provide the foundation for building robust repository and service layers:

```go
package database

import (
    "context"
    "database/sql"
    "fmt"
    "time"
    
    "github.com/google/uuid"
    "your-project/internal/database/sqlc"
)

// QueriesWrapper provides additional functionality on top of generated queries
type QueriesWrapper struct {
    *sqlc.Queries
    db *sql.DB
}

func NewQueriesWrapper(db *sql.DB) *QueriesWrapper {
    return &QueriesWrapper{
        Queries: sqlc.New(db),
        db:      db,
    }
}

// BeginTx starts a transaction and returns queries scoped to that transaction
func (qw *QueriesWrapper) BeginTx(ctx context.Context) (*QueriesWrapper, *sql.Tx, error) {
    tx, err := qw.db.BeginTx(ctx, nil)
    if err != nil {
        return nil, nil, fmt.Errorf("beginning transaction: %w", err)
    }
    
    return &QueriesWrapper{
        Queries: qw.Queries.WithTx(tx),
        db:      qw.db,
    }, tx, nil
}

// CreateUserWithDefaults creates a user with sensible defaults
func (qw *QueriesWrapper) CreateUserWithDefaults(ctx context.Context, email, username, firstName, lastName string) (sqlc.User, error) {
    userUUID := uuid.New()
    
    params := sqlc.CreateUserParams{
        UUID:          userUUID,
        Email:         email,
        Username:      username,
        PasswordHash:  "", // Should be set by caller after hashing
        FirstName:     firstName,
        LastName:      lastName,
        IsActive:      true,
        EmailVerified: false,
    }
    
    return qw.CreateUser(ctx, params)
}

// UpdateUserFields provides a more ergonomic interface for partial updates
func (qw *QueriesWrapper) UpdateUserFields(ctx context.Context, userID int64, updates UserUpdateFields) (sqlc.User, error) {
    params := sqlc.UpdateUserParams{
        ID: userID,
    }
    
    if updates.Email != nil {
        params.Email = updates.Email
    }
    
    if updates.Username != nil {
        params.Username = updates.Username
    }
    
    if updates.FirstName != nil {
        params.FirstName = updates.FirstName
    }
    
    if updates.LastName != nil {
        params.LastName = updates.LastName
    }
    
    if updates.EmailVerified != nil {
        params.EmailVerified = updates.EmailVerified
    }
    
    return qw.UpdateUser(ctx, params)
}

type UserUpdateFields struct {
    Email         *string
    Username      *string
    FirstName     *string
    LastName      *string
    EmailVerified *bool
}

// GetOrdersByDateRange provides a simpler interface for date-based queries
func (qw *QueriesWrapper) GetOrdersByDateRange(ctx context.Context, userID int64, startDate, endDate time.Time) ([]sqlc.Order, error) {
    params := sqlc.SearchOrdersParams{
        UserID:    &userID,
        StartDate: &startDate,
        EndDate:   &endDate,
        Limit:     intPtr(1000), // Default limit
        Offset:    intPtr(0),
    }
    
    rows, err := qw.SearchOrders(ctx, params)
    if err != nil {
        return nil, err
    }
    
    orders := make([]sqlc.Order, len(rows))
    for i, row := range rows {
        orders[i] = row.Order
    }
    
    return orders, nil
}

// Helper functions for pointer conversion
func intPtr(i int64) *int64 {
    return &i
}

func stringPtr(s string) *string {
    return &s
}

func boolPtr(b bool) *bool {
    return &b
}

// Validation helpers for generated types
func (u *User) Validate() error {
    if u.Email == "" {
        return fmt.Errorf("email is required")
    }
    
    if u.Username == "" {
        return fmt.Errorf("username is required")
    }
    
    if u.FirstName == "" {
        return fmt.Errorf("first name is required")
    }
    
    if u.LastName == "" {
        return fmt.Errorf("last name is required")
    }
    
    return nil
}

func (o *Order) IsComplete() bool {
    return o.Status == sqlc.OrderStatusDelivered
}

func (o *Order) CanBeCancelled() bool {
    return o.Status == sqlc.OrderStatusPending || 
           o.Status == sqlc.OrderStatusConfirmed
}

func (o *Order) TotalInDollars() float64 {
    return float64(o.TotalCents) / 100.0
}

// JSON handling helpers for metadata fields
func (p *Product) GetDimensions() (*ProductDimensions, error) {
    if p.DimensionsJson == nil {
        return nil, nil
    }
    
    var dims ProductDimensions
    if err := json.Unmarshal(*p.DimensionsJson, &dims); err != nil {
        return nil, fmt.Errorf("unmarshaling dimensions: %w", err)
    }
    
    return &dims, nil
}

func (p *Product) SetDimensions(dims *ProductDimensions) error {
    if dims == nil {
        p.DimensionsJson = nil
        return nil
    }
    
    data, err := json.Marshal(dims)
    if err != nil {
        return fmt.Errorf("marshaling dimensions: %w", err)
    }
    
    jsonData := json.RawMessage(data)
    p.DimensionsJson = &jsonData
    return nil
}

type ProductDimensions struct {
    Length float64 `json:"length"`
    Width  float64 `json:"width"`
    Height float64 `json:"height"`
    Unit   string  `json:"unit"`
}

type ProductMetadata struct {
    Brand       string            `json:"brand,omitempty"`
    Color       string            `json:"color,omitempty"`
    Size        string            `json:"size,omitempty"`
    Material    string            `json:"material,omitempty"`
    Features    []string          `json:"features,omitempty"`
    Attributes  map[string]string `json:"attributes,omitempty"`
}

func (p *Product) GetMetadata() (*ProductMetadata, error) {
    if p.MetadataJson == nil {
        return &ProductMetadata{}, nil
    }
    
    var meta ProductMetadata
    if err := json.Unmarshal(*p.MetadataJson, &meta); err != nil {
        return nil, fmt.Errorf("unmarshaling metadata: %w", err)
    }
    
    return &meta, nil
}

func (p *Product) SetMetadata(meta *ProductMetadata) error {
    data, err := json.Marshal(meta)
    if err != nil {
        return fmt.Errorf("marshaling metadata: %w", err)
    }
    
    jsonData := json.RawMessage(data)
    p.MetadataJson = &jsonData
    return nil
}
```

This wrapper approach demonstrates how to build ergonomic interfaces on top of the generated sqlc code. The wrapper provides transaction handling, default value management, and helper methods that make the generated code more pleasant to use in application code.

The validation and helper methods show how to extend generated types with business logic while maintaining the benefits of code generation. The JSON handling patterns demonstrate safe ways to work with flexible schema fields while maintaining type safety where possible.

## Repository Pattern Implementation

The repository pattern provides a clean abstraction layer between the database and business logic, enabling testability and maintainability. When combined with sqlc's generated code, repositories become simple adapters that provide domain-specific interfaces.

### Repository Interface Design

Well-designed repository interfaces focus on business operations rather than database implementation details. The interfaces should be comprehensive enough to support all necessary operations while remaining focused on their specific domain:

```go
package repository

import (
    "context"
    "time"
    
    "github.com/google/uuid"
    "your-project/internal/database/sqlc"
    "your-project/internal/domain"
)

// UserRepository defines operations for user data access
type UserRepository interface {
    // Basic CRUD operations
    Create(ctx context.Context, req CreateUserRequest) (*domain.User, error)
    GetByID(ctx context.Context, id int64) (*domain.User, error)
    GetByUUID(ctx context.Context, uuid uuid.UUID) (*domain.User, error)
    GetByEmail(ctx context.Context, email string) (*domain.User, error)
    GetByUsername(ctx context.Context, username string) (*domain.User, error)
    Update(ctx context.Context, id int64, req UpdateUserRequest) (*domain.User, error)
    Delete(ctx context.Context, id int64) error
    
    // Authentication operations
    UpdatePassword(ctx context.Context, id int64, passwordHash string) error
    UpdateLastLogin(ctx context.Context, id int64) error
    VerifyEmail(ctx context.Context, id int64) error
    
    // Query operations
    List(ctx context.Context, req ListUsersRequest) ([]*domain.User, error)
    Count(ctx context.Context, req CountUsersRequest) (int64, error)
    Search(ctx context.Context, query string, limit, offset int) ([]*domain.User, error)
    
    // Analytics operations
    GetStats(ctx context.Context, id int64) (*domain.UserStats, error)
    GetTopCustomers(ctx context.Context, req TopCustomersRequest) ([]*domain.CustomerStats, error)
    
    // Bulk operations
    CreateBatch(ctx context.Context, users []CreateUserRequest) ([]*domain.User, error)
    UpdateBatch(ctx context.Context, updates []UserBatchUpdate) error
}

// OrderRepository defines operations for order data access
type OrderRepository interface {
    // Basic CRUD operations
    Create(ctx context.Context, req CreateOrderRequest) (*domain.Order, error)
    GetByID(ctx context.Context, id int64) (*domain.Order, error)
    GetByUUID(ctx context.Context, uuid uuid.UUID) (*domain.Order, error)
    GetByOrderNumber(ctx context.Context, orderNumber string) (*domain.Order, error)
    Update(ctx context.Context, id int64, req UpdateOrderRequest) (*domain.Order, error)
    Delete(ctx context.Context, id int64) error
    
    // Order-specific operations
    UpdateStatus(ctx context.Context, id int64, status domain.OrderStatus) (*domain.Order, error)
    UpdatePaymentStatus(ctx context.Context, id int64, status domain.PaymentStatus) (*domain.Order, error)
    AddItem(ctx context.Context, orderID int64, req AddOrderItemRequest) (*domain.OrderItem, error)
    RemoveItem(ctx context.Context, orderID, itemID int64) error
    UpdateItemQuantity(ctx context.Context
