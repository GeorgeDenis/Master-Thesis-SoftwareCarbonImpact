-- sql/01_seed.sql
-- Deterministic seed data. The setseed() call below makes the random selections
-- reproducible across runs so that every researcher gets the same dataset.

SELECT setseed(0.42);

-- Shelters: 50 of them
INSERT INTO shelters (name, location)
SELECT 'Shelter #' || i, 'City-' || (i % 10)
FROM generate_series(1, 50) AS g(i);

-- Animals: 10000, distributed across the 50 shelters, with random species and microchip codes.
INSERT INTO animals (name, species, microchip_code, status, shelter_id)
SELECT
    'Animal-' || i,
    (ARRAY['Dog', 'Cat', 'Rabbit', 'Bird', 'Hamster'])[1 + (i % 5)],
    'MC-' || lpad(i::text, 8, '0'),
    'Available',
    1 + (i % 50)
FROM generate_series(1, 10000) AS g(i);

-- Medical records: 30000, on a subset of the animals, with diseases drawn from a small set.
INSERT INTO medical_records (animal_id, disease, treatment, visit_date)
SELECT
    1 + (i % 10000),
    (ARRAY['Parvovirus', 'Distemper', 'Rabies', 'Kennel Cough', 'Heartworm'])[1 + (i % 5)],
    'Treatment-' || i,
    NOW() - (i || ' days')::INTERVAL
FROM generate_series(1, 30000) AS g(i);

-- Adopters: 1000
INSERT INTO adopters (name, email)
SELECT 'Adopter-' || i, 'adopter' || i || '@example.com'
FROM generate_series(1, 1000) AS g(i);

-- Adoptions: 200 (a few animals adopted)
INSERT INTO adoptions (animal_id, adopter_id, adoption_date)
SELECT
    1 + (i % 5000),
    1 + (i % 500),
    NOW() - (i || ' hours')::INTERVAL
FROM generate_series(1, 200) AS g(i);

ANALYZE;
