-- PostgreSQL 17+ | Sprint 1 | 001-create-schemas

CREATE SCHEMA identity;

CREATE SCHEMA household;

CREATE SCHEMA finance;

CREATE SCHEMA income;

REVOKE ALL ON SCHEMA identity, household, finance, income FROM PUBLIC;
