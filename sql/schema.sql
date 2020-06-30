CREATE DATABASE IF NOT EXISTS ipmonitor;

USE ipmonitor;

CREATE TABLE IF NOT EXISTS ips (
    ip VARCHAR(64) NOT NULL PRIMARY KEY,
    ttl BIGINT NOT NULL
);

CREATE USER IF NOT EXISTS 'ipmonitor'@'%' IDENTIFIED WITH mysql_native_password BY 'rotinompi';
GRANT SELECT, INSERT ON ipmonitor.ips TO 'ipmonitor'@'%';
