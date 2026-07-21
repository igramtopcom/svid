package database

import (
	"fmt"
	"time"

	"github.com/snakeloader/backend/internal/config"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	gormlogger "gorm.io/gorm/logger"
)

func NewPostgresDB(cfg config.DatabaseConfig, ginMode string) (*gorm.DB, error) {
	logLevel := gormlogger.Silent
	if ginMode == "debug" {
		logLevel = gormlogger.Warn
	}

	db, err := gorm.Open(postgres.Open(cfg.DSN()), &gorm.Config{
		Logger: gormlogger.Default.LogMode(logLevel),
	})
	if err != nil {
		// Intentionally NOT wrapping the original error — it may contain the DSN with password
		return nil, fmt.Errorf("failed to connect to PostgreSQL (host=%s db=%s): %s", cfg.Host, cfg.DBName, "connection refused or invalid credentials")
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get underlying sql.DB: %w", err)
	}

	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetMaxOpenConns(100)
	sqlDB.SetConnMaxLifetime(time.Hour)

	if err := sqlDB.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping PostgreSQL: %w", err)
	}

	logger.Log.Info().Str("host", cfg.Host).Str("db", cfg.DBName).Msg("PostgreSQL connected")
	return db, nil
}
