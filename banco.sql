-- =============================================================================
-- BANCO DE DADOS - ROBÔ DE ROÇAGEM DE GRAMA
-- SQL Aplicado ao Challenge - Sprint 3
-- =============================================================================
-- Tabelas: sessoes_rojagem + leituras_sensores
-- Dados: simulados com script Python (simular.py)
-- Motor: PostgreSQL
-- =============================================================================

-- =============================================================================
-- 1. CRIAÇÃO DAS TABELAS
-- =============================================================================

-- Sessões de roçagem: cada sessão é uma operação completa do robô
-- em um trecho do acostamento.
CREATE TABLE IF NOT EXISTS sessoes_rojagem (
    id                  SERIAL PRIMARY KEY,
    nome                VARCHAR(100) NOT NULL,
    data_inicio         TIMESTAMP NOT NULL,
    data_fim            TIMESTAMP NOT NULL,
    distancia_total_m   NUMERIC(8,3) NOT NULL,
    duracao_min         NUMERIC(4,1) NOT NULL,
    area_total_m2       NUMERIC(8,2) NOT NULL
);

-- Leituras de sensores: uma linha por leitura a cada 5 segundos.
-- Contém dados do giroscópio (pitch), ultrassom (distância ao solo),
-- sensor de vibração e flag de detecção de desnível.
CREATE TABLE IF NOT EXISTS leituras_sensores (
    id                   SERIAL PRIMARY KEY,
    sessao_id            INT NOT NULL REFERENCES sessoes_rojagem(id)
        ON DELETE CASCADE,
    timestamp            TIMESTAMP NOT NULL,
    posicao_x_m          NUMERIC(8,3) NOT NULL,
    altitude_z_m         NUMERIC(8,4) NOT NULL,
    pitch_rad            NUMERIC(8,6) NOT NULL,
    dist_us_cm           NUMERIC(7,2) NOT NULL,
    vibracao_g           NUMERIC(7,4) NOT NULL,
    desnivel_detected    BOOLEAN NOT NULL DEFAULT FALSE
);

-- Índices para as consultas mais frequentes
CREATE INDEX IF NOT EXISTS idx_leituras_sessao ON leituras_sensores(sessao_id);
CREATE INDEX IF NOT EXISTS idx_leituras_ts     ON leituras_sensores(timestamp);

-- =============================================================================
-- 2. CARGA DE DADOS (via \copy no psql — não requer superusuário)
-- =============================================================================
-- Execute no psql, na mesma pasta do arquivo:
--   \i banco.sql
--
-- Os arquivos CSV foram gerados pelo script simular.py em dados/.
-- Nota: as tabelas usam SERIAL para id, então os CSVs de leitura não
-- devem incluir a coluna id. O \copy abaixo lista apenas as colunas
-- não-SERIAL.
-- =============================================================================

\copy sessoes_rojagem (id, nome, data_inicio, data_fim,
       distancia_total_m, duracao_min, area_total_m2)
    FROM 'dados/sessoes.csv' WITH (FORMAT CSV, HEADER true);

\copy leituras_sensores (sessao_id, timestamp, posicao_x_m,
       altitude_z_m, pitch_rad, dist_us_cm, vibracao_g,
       desnivel_detected)
    FROM 'dados/leituras_sessao1.csv' WITH (FORMAT CSV, HEADER true);

\copy leituras_sensores (sessao_id, timestamp, posicao_x_m,
       altitude_z_m, pitch_rad, dist_us_cm, vibracao_g,
       desnivel_detected)
    FROM 'dados/leituras_sessao2.csv' WITH (FORMAT CSV, HEADER true);

\copy leituras_sensores (sessao_id, timestamp, posicao_x_m,
       altitude_z_m, pitch_rad, dist_us_cm, vibracao_g,
       desnivel_detected)
    FROM 'dados/leituras_sessao3.csv' WITH (FORMAT CSV, HEADER true);

-- =============================================================================
-- 3. CONSULTAS SQL — 5 PERGUNTAS PARA A EMPRESA
-- =============================================================================
-- Cada consulta responde a uma pergunta de negócio usando os recursos
-- exigidos: WHERE, ORDER BY / LIMIT, funções de agregação (COUNT, MAX),
-- GROUP BY e JOIN.

-- ---------------------------------------------------------------------------
-- PERGUNTA 1
-- Qual o maior desnível (transição entre níveis) que o robô enfrentou
-- em cada sessão de roçagem?
-- =============================================================================
-- Conceitos: JOIN, MAX, GROUP BY, subconsulta com LAG
-- Um desnível é a diferença de altitude entre leituras consecutivas.
-- Usamos LAG() para comparar cada leitura com a anterior, dentro de cada
-- sessão, e MAX(ABS(delta)) para pegar o maior salto.
-- =============================================================================

SELECT
    s.nome                                          AS sessao,
    ROUND(MAX(ABS(l.delta_z)), 4)                  AS maior_desnivel_m
FROM (
    SELECT
        sessao_id,
        altitude_z_m - LAG(altitude_z_m) OVER (
            PARTITION BY sessao_id ORDER BY timestamp
        ) AS delta_z
    FROM leituras_sensores
) l
JOIN sessoes_rojagem s ON s.id = l.sessao_id
WHERE l.delta_z IS NOT NULL                        -- primeira leitura não tem anterior
GROUP BY s.id, s.nome
ORDER BY maior_desnivel_m DESC;

-- ---------------------------------------------------------------------------
-- PERGUNTA 2
-- Quantos desníveis (transições entre níveis) foram registrados em cada
-- sessão de roçagem?
-- =============================================================================
-- Conceitos: JOIN, COUNT, WHERE (FILTER), GROUP BY
-- Cada leitura com desnivel_detected = TRUE representa um desnível detectado
-- pelo algoritmo (variação de altitude > 7 cm entre leituras consecutivas).
-- =============================================================================

SELECT
    s.nome                                          AS sessao,
    COUNT(*) FILTER (WHERE l.desnivel_detected)    AS qtd_desniveis
FROM sessoes_rojagem s
JOIN leituras_sensores l ON l.sessao_id = s.id
GROUP BY s.id, s.nome
ORDER BY qtd_desniveis DESC;

-- ---------------------------------------------------------------------------
-- PERGUNTA 3
-- Qual é a área total roçada por minuto em cada sessão?
-- =============================================================================
-- Conceitos: divisão numérica, ORDER BY
-- Área por minuto = área_total_m2 / duracao_min.
-- A empresa pode usar essa metrica para comparar produtividade entre sessões.
-- =============================================================================

SELECT
    s.nome                                          AS sessao,
    ROUND(s.area_total_m2 / s.duracao_min, 2)     AS area_m2_por_minuto
FROM sessoes_rojagem s
ORDER BY area_m2_por_minuto DESC;

-- ---------------------------------------------------------------------------
-- PERGUNTA 4
-- Quantos km o robô percorreu por minuto em cada sessão?
-- =============================================================================
-- Conceitos: divisão, ORDER BY
-- Distância percorrida (em metros) convertida para km e dividida pelo tempo.
-- =============================================================================

SELECT
    s.nome                                          AS sessao,
    ROUND(s.distancia_total_m / 1000.0 / s.duracao_min, 4)
                                                    AS km_por_minuto
FROM sessoes_rojagem s
ORDER BY km_por_minuto DESC;

-- ---------------------------------------------------------------------------
-- PERGUNTA 5
-- Qual o maior ângulo de inclinação (pitch) que o robô alcançou em cada
-- sessão, em graus?
-- =============================================================================
-- Conceitos: JOIN, MAX, GROUP BY, conversão radianos → graus
-- O pitch do giroscópio mede o ângulo de inclinação frontal do robô ao
-- encontrar irregularidades no terreno. Converter para graus ajuda a
-- interpretar a magnitude do esforço sofrido.
-- =============================================================================

SELECT
    s.nome                                          AS sessao,
    ROUND(MAX(ABS(l.pitch_rad)) * 180.0 / PI(), 2)
                                                    AS maior_angulo_graus
FROM sessoes_rojagem s
JOIN leituras_sensores l ON l.sessao_id = s.id
GROUP BY s.id, s.nome
ORDER BY maior_angulo_graus DESC;
