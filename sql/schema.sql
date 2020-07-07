CREATE DATABASE IF NOT EXISTS ipmonitor;

USE ipmonitor;

CREATE TABLE IF NOT EXISTS ips (
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    tble VARCHAR(16) NOT NULL,
    ip VARCHAR(64) NOT NULL,
    ttl BIGINT NOT NULL
);

CREATE USER IF NOT EXISTS 'ipmonitor'@'%' IDENTIFIED WITH mysql_native_password BY 'rotinompi';
GRANT SELECT, INSERT ON ipmonitor.ips TO 'ipmonitor'@'%';

CREATE INDEX tble_ip ON ips (tble, ip);
