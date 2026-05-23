-- sql/00_schema.sql
-- PostgreSQL schema for PetRescue.NET. Five tables matching the dissertation.

DROP TABLE IF EXISTS adoptions CASCADE;
DROP TABLE IF EXISTS medical_records CASCADE;
DROP TABLE IF EXISTS adopters CASCADE;
DROP TABLE IF EXISTS animals CASCADE;
DROP TABLE IF EXISTS shelters CASCADE;

CREATE TABLE shelters (
    id       SERIAL PRIMARY KEY,
    name     VARCHAR(255) NOT NULL,
    location VARCHAR(255) NOT NULL
);

CREATE TABLE animals (
    id              SERIAL PRIMARY KEY,
    name            VARCHAR(255) NOT NULL,
    species         VARCHAR(255) NOT NULL,
    microchip_code  VARCHAR(100) NOT NULL,
    status          VARCHAR(50)  NOT NULL DEFAULT 'Available',
    shelter_id      INT NOT NULL REFERENCES shelters(id)
);

CREATE TABLE medical_records (
    id          SERIAL PRIMARY KEY,
    animal_id   INT NOT NULL REFERENCES animals(id),
    disease     VARCHAR(255) NOT NULL,
    treatment   VARCHAR(255) NOT NULL,
    visit_date  TIMESTAMP NOT NULL
);
-- NB: No index on medical_records.disease in the baseline.

CREATE TABLE adopters (
    id    SERIAL PRIMARY KEY,
    name  VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL
);

CREATE TABLE adoptions (
    id            SERIAL PRIMARY KEY,
    animal_id     INT NOT NULL REFERENCES animals(id),
    adopter_id    INT NOT NULL REFERENCES adopters(id),
    adoption_date TIMESTAMP NOT NULL
);
