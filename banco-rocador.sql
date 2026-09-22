-- =============================================================================
-- BANCO DE DADOS - ROBÔ DE ROÇAGEM DE GRAMA
-- SQL Aplicado ao Challenge - Sprint 3
-- Tabelas: sessoes_rocagem + leituras_sensores
-- Dados: simulados com script Python (simular.py)
-- =============================================================================

-- =============================================================================
-- 1. CRIAÇÃO DAS TABELAS
-- =============================================================================

CREATE TABLE IF NOT EXISTS sessoes_rocagem (
    id                  SERIAL PRIMARY KEY,
    nome                VARCHAR(100) NOT NULL,
    data_inicio         TIMESTAMP NOT NULL,
    data_fim            TIMESTAMP NOT NULL,
    distancia_total_m   NUMERIC(8,3) NOT NULL,
    duracao_min         NUMERIC(4,1) NOT NULL,
    area_total_m2       NUMERIC(8,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS leituras_sensores (
    id                   SERIAL PRIMARY KEY,
    sessao_id            INT NOT NULL REFERENCES sessoes_rocagem(id) ON DELETE CASCADE,
    timestamp            TIMESTAMP NOT NULL,
    posicao_x_m          NUMERIC(8,3) NOT NULL,
    altitude_z_m         NUMERIC(8,4) NOT NULL,
    pitch_rad            NUMERIC(8,6) NOT NULL,
    dist_us_cm           NUMERIC(7,2) NOT NULL,
    vibracao_g           NUMERIC(7,4) NOT NULL,
    desnivel_detected    BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_leituras_sessao ON leituras_sensores(sessao_id);
CREATE INDEX IF NOT EXISTS idx_leituras_ts     ON leituras_sensores(timestamp);

-- =============================================================================
-- 2. CARGA DE DADOS
--    Dos CSVs gerados por simular.py em C:/Users/Leona/dados/
-- =============================================================================

COPY sessoes_rocagem (id, nome, data_inicio, data_fim, distancia_total_m, duracao_min, area_total_m2)
    FROM 'C:/Users/Leona/dados/sessoes.csv' WITH (FORMAT CSV, HEADER true);

COPY leituras_sensores (sessao_id, timestamp, posicao_x_m, altitude_z_m, pitch_rad, dist_us_cm, vibracao_g, desnivel_detected)
    FROM 'C:/Users/Leona/dados/leituras_sessao1.csv' WITH (FORMAT CSV, HEADER true);

COPY leituras_sensores (sessao_id, timestamp, posicao_x_m, altitude_z_m, pitch_rad, dist_us_cm, vibracao_g, desnivel_detected)
    FROM 'C:/Users/Leona/dados/leituras_sessao2.csv' WITH (FORMAT CSV, HEADER true);

COPY leituras_sensores (sessao_id, timestamp, posicao_x_m, altitude_z_m, pitch_rad, dist_us_cm, vibracao_g, desnivel_detected)
    FROM 'C:/Users/Leona/dados/leituras_sessao3.csv' WITH (FORMAT CSV, HEADER true);

-- =============================================================================
-- 3. CONSULTAS — 5 PERGUNTAS PARA A EMPRESA
-- =============================================================================

-- PERGUNTA 1: Qual o maior desnível que o robô enfrentou em cada sessão?
-- Conceitos: JOIN, MAX, GROUP BY, LAG (window function)
SELECT
    s.nome                                          AS sessao,
    ROUND(MAX(ABS(l.delta_z))::numeric, 4)         AS maior_desnivel_m
FROM (
    SELECT
        sessao_id,
        altitude_z_m - LAG(altitude_z_m) OVER (
            PARTITION BY sessao_id ORDER BY timestamp
        ) AS delta_z
    FROM leituras_sensores
) l
JOIN sessoes_rocagem s ON s.id = l.sessao_id
WHERE l.delta_z IS NOT NULL
GROUP BY s.id, s.nome
ORDER BY maior_desnivel_m DESC;

-- PERGUNTA 2: Quantos desníveis foram registrados em cada sessão?
-- Conceitos: JOIN, COUNT, FILTER, GROUP BY
SELECT
    s.nome                                          AS sessao,
    COUNT(*) FILTER (WHERE l.desnivel_detected)    AS qtd_desniveis
FROM sessoes_rocagem s
JOIN leituras_sensores l ON l.sessao_id = s.id
GROUP BY s.id, s.nome
ORDER BY qtd_desniveis DESC;

-- PERGUNTA 3: Qual é a área total roçada por minuto em cada sessão?
-- Conceitos: divisão numérica, ORDER BY
SELECT
    s.nome                                          AS sessao,
    ROUND(s.area_total_m2 / s.duracao_min, 2)     AS area_m2_por_minuto
FROM sessoes_rocagem s
ORDER BY area_m2_por_minuto DESC;

-- PERGUNTA 4: Quantos km o robô percorreu por minuto em cada sessão?
-- Conceitos: divisão, ORDER BY
SELECT
    s.nome                                          AS sessao,
    ROUND(s.distancia_total_m / 1000.0 / s.duracao_min, 4)
                                                    AS km_por_minuto
FROM sessoes_rocagem s
ORDER BY km_por_minuto DESC;

-- PERGUNTA 5: Qual o maior ângulo de inclinação (pitch) em cada sessão, em graus?
-- Conceitos: JOIN, MAX, GROUP BY, conversão radianos → graus
SELECT
    s.nome                                          AS sessao,
    ROUND((MAX(ABS(l.pitch_rad)) * 180.0 / PI())::numeric, 2)
                                                    AS maior_angulo_graus
FROM sessoes_rocagem s
JOIN leituras_sensores l ON l.sessao_id = s.id
GROUP BY s.id, s.nome
ORDER BY maior_angulo_graus DESC;
