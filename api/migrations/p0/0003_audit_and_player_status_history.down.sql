DROP TABLE IF EXISTS player_status_periods;
ALTER TABLE audit_logs
    DROP INDEX idx_audit_operation_id,
    DROP INDEX idx_audit_club_operation,
    DROP COLUMN operation_id,
    DROP COLUMN device_info,
    DROP COLUMN ip_address,
    DROP COLUMN reason,
    DROP COLUMN operation,
    DROP COLUMN player_id,
    DROP COLUMN club_id;
