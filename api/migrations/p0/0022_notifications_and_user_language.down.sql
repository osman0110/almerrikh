-- Intentionally a no-op: dropping the notifications table would erase the
-- club's notification history, and users.language may pre-date this
-- migration. Remove manually only after exporting both.
SELECT 1;
